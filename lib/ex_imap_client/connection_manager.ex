defmodule ExImapClient.ConnectionManager do
  @moduledoc false

  alias ExImapClient.{
    ClientConnection
  }

  def start_link() do
    DynamicSupervisor.start_link(name: __MODULE__, strategy: :one_for_one)
  end

  def start_connection(identifier) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {ClientConnection, identifier}
    )
  end

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end
end
