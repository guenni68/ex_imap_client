defmodule ExImapClient.ClientConnection do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function], restart: :transient
  require Logger

  alias ExImapClient.RequestResponseHandler, as: Handler

  alias ExImapClient.{
    ProcessRegistry,
    ResponseTracer
  }

  @disconnected :disconnected
  @connected_tcp :connected_tcp
  @connected_ssl :connected_ssl

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

  defp via_tuple(identifier) do
    ProcessRegistry.via_tuple(identifier)
  end

  @impl GenStateMachine
  def init(_) do
    {:ok, @disconnected, new_data()}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {@connect_tcp, hostname, port},
        @disconnected,
        data
      ) do
    actions = [{:next_event, :internal, {@connect_tcp, hostname, port, from}}]

    {:keep_state_and_data, actions}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {connect_type, hostname, port},
        @disconnected,
        data
      ) do
    actions = [{:next_event, :internal, {connect_type, hostname, port, from}}]

    {:keep_state_and_data, actions}
  end

  @impl GenStateMachine
  def handle_event(
        :internal,
        {connect_type, hostname, port, from},
        @disconnected,
        data
      ) do
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

    case connect_type do
      @connect_ssl ->
        {:ok, socket} = :ssl.connect(hostname_charlist, port, opts)
        {:next_state, {@connected_ssl, socket, handler}, updated_data}

      @connect_tcp ->
        {:ok, socket} = :gen_tcp.connect(hostname_charlist, port, opts)
        {:next_state, {@connected_tcp, socket, handler}, updated_data}
    end
  end

  @impl GenStateMachine
  def handle_event(:info, {:tcp, tcp, message}, {@connected_tcp, tcp, handler}, data) do
    {actions, new_handler} = handle_response(message, handler)
    {:next_state, {@connected_tcp, tcp, new_handler}, data, actions}
  end

  @impl GenStateMachine
  def handle_event(:info, {:ssl, ssl, message}, {@connected_ssl, ssl, handler}, data) do
    {actions, new_handler} = handle_response(message, handler)
    {:next_state, {@connected_ssl, ssl, new_handler}, data, actions}
  end

  @impl GenStateMachine
  def handle_event(:info, {:tcp_closed, tcp}, {@connected_tcp, tcp, handler}, data) do
    # TODO
    actions = []
    {:next_state, @disconnected, new_data(), actions}
  end

  @impl GenStateMachine
  def handle_event(:info, {:ssl_closed, ssl}, {@connected_ssl, ssl, handler}, data) do
    # TODO
    actions = []
    {:next_state, @disconnected, new_data(), actions}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:send, command_string},
        {connection_type, socket, handler},
        data
      ) do
    parser = response_parser_from_rule("response")

    {tag, new_handler} =
      handler
      |> Handler.handle_request(from, parser)

    request = "#{tag} #{command_string}\r\n"

    case connection_type do
      @connected_tcp ->
        :gen_tcp.send(socket, request)

      @connected_ssl ->
        :ssl.send(socket, request)
    end

    {:next_state, {connection_type, socket, new_handler}, data}
  end

  defp handle_response(response, handler) do
    ResponseTracer.trace_response(response)

    case Handler.handle_response(handler, response) do
      {:ok, {:result, {from, ast}, new_handler}} ->
        Logger.debug("Parsed response")
        ResponseTracer.start_new_trace()
        actions = [{:reply, from, {:ok, ast}}]
        {actions, new_handler}

      {:ok, {:continue, new_handler}} ->
        Logger.debug("response part received")
        {[], new_handler}

      # TODO
      {:error, :empty_queue} ->
        {[], handler}

      {:error, reason} ->
        {[], handler}
    end
  end

  defp response_parser_from_rule(rule_name \\ "response") do
    fn overrides ->
      ImapResponseParser.from_rule_name(overrides, rule_name)
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
end
