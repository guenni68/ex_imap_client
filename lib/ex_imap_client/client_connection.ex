defmodule ExImapClient.ClientConnection do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function], restart: :transient
  require Logger

  alias ExImapClient.RequestResponseHandler, as: Handler

  alias ExImapClient.{
    ProcessRegistry,
    ResponseTracer,
    ResponseParser
  }

  @disconnected :disconnected
  @connected_tcp :connected_tcp
  @connected_ssl :connected_ssl

  @beginning_conversation :beginning_conversation
  @continuing_conversation :continuing_conversation

  @continue_conversation :continue_conversation

  @connect_tcp :connect_tcp
  @connect_ssl :connect_ssl

  def start_link(identifier) do
    GenStateMachine.start_link(__MODULE__, %{}, name: via_tuple(identifier))
  end

  def connect_tcp(identifier, hostname, port) do
    connect(identifier, hostname, port, @connect_tcp)
  end

  def connect_ssl(identifier, hostname, port) do
    connect(identifier, hostname, port, @connect_ssl)
  end

  defp connect(identifier, hostname, port, connection_type) do
    GenStateMachine.call(via_tuple(identifier), {connection_type, hostname, port}, 5_000)
  end

  def send_to_server(identifier, command_string, timeout) do
    GenStateMachine.call(via_tuple(identifier), {:send, command_string}, timeout)
  end

  def begin_conversation(identifier, message) do
    GenStateMachine.call(via_tuple(identifier), {:begin_conversation, message})
  end

  def continue_conversation(identifier, token, message) do
    GenStateMachine.call(via_tuple(identifier), {@continue_conversation, token, message})
  end

  defp via_tuple(identifier) do
    ProcessRegistry.via_tuple(identifier)
  end

  @impl GenStateMachine
  def init(_) do
    {:ok, @disconnected, new_data()}
  end

  @impl GenStateMachine
  def handle_event(type, payload, @disconnected, data) do
    disconnected(type, payload, data)
  end

  @impl GenStateMachine
  def handle_event(type, payload, {@connected_tcp = conn_type, socket, handler}, data) do
    connected(type, payload, conn_type, socket, handler, data)
  end

  @impl GenStateMachine
  def handle_event(type, payload, {@connected_ssl = conn_type, socket, handler}, data) do
    connected(type, payload, conn_type, socket, handler, data)
  end

  @impl GenStateMachine
  def handle_event(type, payload, {@beginning_conversation, state}, data) do
    beginning_conversation(type, payload, state, data)
  end

  @impl GenStateMachine
  def handle_event(type, payload, {@continuing_conversation, token, state}, data) do
    continuing_conversation(type, payload, token, state, data)
  end

  # by state
  defp disconnected(type, payload, data)

  defp disconnected(
         {:call, from},
         {conn_type, hostname, port},
         data
       )
       when conn_type in [@connect_tcp, @connect_ssl] do
    parser = response_parser_from_rule("greeting")

    {_tag, handler} =
      Handler.new()
      |> Handler.handle_request(from, parser)

    hostname_charlist =
      hostname
      |> String.to_charlist()

    opts = [:binary, active: true]

    updated_data =
      data
      |> set_hostname(hostname)
      |> set_port(port)

    case conn_type do
      @connect_ssl ->
        case :ssl.connect(hostname_charlist, port, opts) do
          {:ok, socket} ->
            {:next_state, {@connected_ssl, socket, handler}, updated_data}

          error ->
            actions = [
              {:reply, from, {:error, error}}
            ]

            {:keep_state_and_data, actions}
        end

      @connect_tcp ->
        case :gen_tcp.connect(hostname_charlist, port, opts) do
          {:ok, socket} ->
            {:next_state, {@connected_tcp, socket, handler}, updated_data}

          {:error, _reason} = error ->
            actions = [
              {:reply, from, error}
            ]

            {:keep_state_and_data, actions}
        end
    end
  end

  defp disconnected(
         {:call, from},
         _payload,
         _data
       ) do
    actions = [{:reply, from, {:error, @disconnected}}]
    {:keep_state_and_data, actions}
  end

  defp connected(type, payload, conn_type, socket, handler, data)

  defp connected({:call, from}, {:send, command_string}, conn_type, socket, handler, data) do
    parser = response_parser_from_rule("response")

    {tag, new_handler} =
      handler
      |> Handler.handle_request(from, parser)

    request = "#{tag} #{command_string}\r\n"

    send_over_socket(conn_type, socket, request)

    {:next_state, {conn_type, socket, new_handler}, data}
  end

  defp connected(
         {:call, from},
         {:begin_conversation, message},
         conn_type,
         socket,
         handler,
         data
       ) do
    parser = conversation_parser_from_rule()

    {tag, new_handler} =
      handler
      |> Handler.handle_request(from, parser)

    request = "#{tag} #{message}\r\n"

    send_over_socket(conn_type, socket, request)

    {:next_state, {@beginning_conversation, {conn_type, socket, new_handler}}, data}
  end

  defp connected(
         :info,
         {ssl_or_tcp, socket, response},
         conn_type,
         socket,
         handler,
         data
       )
       when ssl_or_tcp in [:tcp, :ssl] do
    case Handler.handle_response(handler, response) do
      {:ok, {:result, {from, ast}, new_handler}} ->
        Logger.debug("Parsed response")
        ResponseTracer.start_new_trace()
        actions = [{:reply, from, {:ok, ast}}]

        {:next_state, {conn_type, socket, new_handler}, data, actions}

      {:ok, {:continue, new_handler}} ->
        Logger.debug("response part received")
        {:next_state, {conn_type, socket, new_handler}, data}

      {:ok, {:partial_result, {from, ast}, new_handler}} ->
        actions = [{:reply, from, {:ok, ast}}]
        {:next_state, {conn_type, socket, new_handler}, data, actions}

      # TODO
      {:error, :empty_queue} ->
        :keep_state_and_data

      {:error, _reason} ->
        :keep_state_and_data
    end
  end

  defp connected(
         :info,
         {ssl_or_tcp_closed, socket},
         _conn_type,
         socket,
         _handler,
         %{
           hostname: _hostname,
           port: _port
         }
       )
       when ssl_or_tcp_closed in [:ssl_closed, :tcp_closed] do
    Logger.debug("#{ssl_or_tcp_closed} connection closed")
    actions = []

    {:next_state, @disconnected, new_data(), actions}
  end

  defp beginning_conversation(type, payload, state, data)

  defp beginning_conversation(
         :info,
         {tcp_or_ssl, socket, response},
         {conn_type, socket, handler},
         data
       )
       when tcp_or_ssl in [:tcp, :ssl] do
    case Handler.handle_response(handler, response) do
      {:ok, {:partial_result, {from, result}, new_handler}} ->
        conversation_token = make_ref()
        actions = [{:reply, from, {:ok, result, conversation_token}}]
        new_state = {conn_type, socket, new_handler}

        {
          :next_state,
          {@continuing_conversation, conversation_token, new_state},
          data,
          actions
        }
    end
  end

  defp continuing_conversation(type, payload, token, state, data)

  # TODO wrap sending over socket
  defp continuing_conversation(
         {:call, from},
         {@continue_conversation, token, message},
         token,
         {conn_type, socket, handler},
         data
       ) do
    new_handler = Handler.continue_conversation(handler, from)
    new_state = {@continuing_conversation, token, {conn_type, socket, new_handler}}
    message = "#{message}\r\n"

    send_over_socket(conn_type, socket, message)

    {:next_state, new_state, data}
  end

  # incoming response
  defp continuing_conversation(
         :info,
         {tcp_or_ssl, socket, response},
         token,
         {conn_type, socket, handler},
         data
       )
       when tcp_or_ssl in [:tcp, :ssl] do
    # TODO implement other cases
    case Handler.handle_response(handler, response) do
      {:ok, {:result, {from, result}, new_handler}} ->
        actions = [{:reply, from, {:ok, result}}]
        new_state = {conn_type, socket, new_handler}
        {:next_state, new_state, data, actions}

      {:ok, {:partial_result, {from, ast}, new_handler}} ->
        actions = [{:reply, from, {:ok, ast}}]
        new_state = {@continuing_conversation, token, {conn_type, socket, new_handler}}
        {:next_state, new_state, data, actions}
    end
  end

  # helpers

  defp response_parser_from_rule(rule_name \\ "response") do
    fn overrides ->
      ResponseParser.from_rule_name(overrides, rule_name)
    end
  end

  defp conversation_parser_from_rule(rule_name \\ "conversation") do
    fn overrides ->
      overrides
      |> ResponseParser.from_rule_name(rule_name)
      |> ResponseParser.streaming_parser()
    end
  end

  defp new_data() do
    %{}
  end

  defp set_hostname(data, hostname) do
    data
    |> Map.put(:hostname, hostname)
  end

  defp set_port(data, port) do
    data
    |> Map.put(:port, port)
  end

  defp send_over_socket(conn_type, socket, message) do
    case conn_type do
      @connected_ssl ->
        :ssl.send(socket, message)

      @connected_tcp ->
        :gen_tcp.send(socket, message)
    end
  end
end
