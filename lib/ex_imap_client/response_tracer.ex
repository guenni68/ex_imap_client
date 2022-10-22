defmodule ExImapClient.ResponseTracer do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function]

  @disconnected :disconnected
  @connected :connected

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
    {:ok, @disconnected, path, actions}
  end

  @impl GenStateMachine
  def handle_event(:cast, {:trace_response, response}, {@connected, handle}, _path) do
    IO.write(handle, response)

    :keep_state_and_data
  end

  @impl GenStateMachine
  def handle_event(:cast, {:trace_response, response}, @disconnected, path) do
    case new_handle(path) do
      {:ok, handle} ->
        IO.write(handle, response)
        {:next_state, {@connected, handle}, path}

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:cast, :start_new_trace, {@connected, handle}, path) do
    File.close(handle)
    {:next_state, @disconnected, path}
  end

  @impl GenStateMachine
  def handle_event(:internal, :initialize, @disconnected, path) do
    with :ok <- File.mkdir_p(path),
         {:ok, handle} <- new_handle(path) do
      {:next_state, {@connected, handle}, path}
    else
      _ ->
        :keep_state_and_data
    end
  end

  defp new_handle(path) do
    Path.join([path, "trace.txt"])
    |> File.open([:write, :utf8])
  end
end
