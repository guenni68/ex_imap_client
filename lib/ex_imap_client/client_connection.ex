defmodule ExImapClient.ClientConnection do
  @moduledoc false

  use GenStateMachine, restart: :temporary
  require Logger
  alias ExImapClient.ProcessRegistry

  def start_link(identifier) do
    GenStateMachine.start_link(__MODULE__, %{}, name: via_tuple(identifier))
  end

  defp via_tuple(identifier) do
    ProcessRegistry.via_tuple(identifier)
  end

  def connect_and_login(identifier, hostname, port, username, password) do
    GenStateMachine.call(
      via_tuple(identifier),
      {:connect_and_login, hostname, port, username, password}
    )
  end

  def init(data) do
    Logger.debug("client connection process started")
    {:ok, :disconnected, data}
  end

  def handle_event(
        {:call, from},
        {:connect_and_login, hostname, port, username, password},
        :disconnected,
        data
      ) do
    hostname =
      hostname
      |> String.to_charlist()

    opts = [:binary, active: false]

    with {:ok, socket} <- :gen_tcp.connect(hostname, port, opts),
         {:ok, capabilities} <- :gen_tcp.recv(socket, 0),
         :ok <- :gen_tcp.send(socket, "A001 LOGIN #{username} #{password}\r\n"),
         {:ok, login_response} <- :gen_tcp.recv(socket, 0),
         :ok <- :inet.setopts(socket, active: true) do
      actions = [{:reply, from, {:ok, {:logged_in, capabilities, login_response}}}]
      {:next_state, {:authenticated, socket}, data, actions}
    else
      error ->
        {:stop_and_reply, :normal, [{:reply, from, error}]}
    end
  end

  def handle_event(:info, {:tcp_closed, socket}, state, data) do
    :stop
  end

  def handle_event(:info, {:tcp, socket, message}, state, data) do
    Logger.debug(message)
    :keep_state_and_data
  end

  def terminate(reason, state, data) do
    Logger.debug("terminating #{inspect(reason)} #{inspect(state)}")
    :ok
  end
end
