defmodule ExImapClient.Util do
  @moduledoc false

  require Logger
  alias ExImapClient.{ConnectionManager, ClientConnection}

  def create_unique_imap_connection_identifier(hostname, port, username, password) do
    {hostname, port, username, password}
  end

  def start_imap_connection(hostname, port, username, password) do
    start_imap_connection(
      hostname,
      port,
      username,
      password,
      create_unique_imap_connection_identifier(hostname, port, username, password)
    )
  end

  def start_imap_connection(hostname, port, username, password, identifier) do
    with {:ok, _pid} <- ConnectionManager.start_connection(identifier),
         {:ok, :logged_in, capabilities, login_msg} <-
           ClientConnection.connect_and_login(
             identifier,
             hostname,
             port,
             username,
             password
           ) do
      Logger.debug(capabilities)
      {:ok, identifier}
    end
  end
end
