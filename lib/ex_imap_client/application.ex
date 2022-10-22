defmodule ExImapClient.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExImapClient.{
    ProcessRegistry,
    ConnectionManager,
    ResponseTracer
  }

  @impl true
  def start(_type, _args) do
    children = [
      ProcessRegistry,
      ConnectionManager,
      {ResponseTracer, "notes/debug"}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExImapClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
