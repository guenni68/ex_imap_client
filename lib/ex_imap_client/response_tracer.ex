defmodule ExImapClient.ResponseTracer do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function]

  @closed :closed
  @open :open

  def start_link(base_path) do
    GenStateMachine.start_link(__MODULE__, base_path, name: __MODULE__)
  end

  def trace_response(response) do
    GenStateMachine.cast(__MODULE__, {:trace_response, response})
  end

  def start_new_trace() do
    GenStateMachine.cast(__MODULE__, :start_new_trace)
  end

  @impl GenStateMachine
  def init(path) do
    actions = [{:next_event, :internal, :initialize}]
    {:ok, @closed, path, actions}
  end

  @impl GenStateMachine
  def handle_event(type, payload, @closed, data) do
    handle_closed(type, payload, data)
  end

  @impl GenStateMachine
  def handle_event(type, payload, {@open, handle}, data) do
    handle_open(type, payload, handle, data)
  end

  defp handle_closed(type, payload, data)

  defp handle_closed(:cast, {:trace_response, response}, path) do
    case new_handle(path) do
      {:ok, handle} ->
        IO.write(handle, response)
        {:next_state, {@open, handle}, path}

      _ ->
        :keep_state_and_data
    end
  end

  defp handle_closed(:internal, :initialize, path) do
    with :ok <- File.mkdir_p(path),
         {:ok, handle} <- new_handle(path) do
      {:next_state, {@open, handle}, path}
    else
      _ ->
        :keep_state_and_data
    end
  end

  defp handle_closed(:cast, :start_new_trace, path) do
    handle = File.open(path)

    {:next_state, {@open, handle}, path}
  end

  defp handle_open(type, payload, handle, data)

  defp handle_open(:cast, {:trace_response, response}, handle, _data) do
    IO.write(handle, response)

    :keep_state_and_data
  end

  defp handle_open(:cast, :start_new_trace, handle, path) do
    File.close(handle)
    {:next_state, @closed, path}
  end

  defp new_handle(path) do
    Path.join([path, "trace.txt"])
    |> File.open([:write, :utf8])
  end
end
