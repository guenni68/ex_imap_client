defmodule ExImapClient do
  require Logger

  alias ExImapClient.{
    ConnectionManager,
    ClientConnection
  }

  def start_connection(hostname, port \\ 143) do
    start_imap_connection(
      hostname,
      port,
      &ClientConnection.connect_tcp/3
    )
  end

  def start_connection_ssl(hostname, port \\ 993) do
    start_imap_connection(
      hostname,
      port,
      &ClientConnection.connect_ssl/3
    )
  end

  def login_plain(identifier, username, password) do
    send_to_server(identifier, "LOGIN #{username} #{password}")
  end

  def logout(identifier) do
    send_to_server(identifier, "LOGOUT")
  end

  def list(identifier, from \\ "*", to \\ "*") do
    send_to_server(identifier, "LIST #{from} #{to}")
  end

  def noop(identifier) do
    send_to_server(identifier, "NOOP")
  end

  def bad_request(identifier) do
    send_to_server(identifier, "bad request, intentionally")
  end

  def status(identifier, mailbox, query \\ "MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN") do
    send_to_server(identifier, "STATUS #{mailbox} (#{query})")
  end

  def select(identifier, mailbox) do
    send_to_server(identifier, "SELECT #{mailbox}")
  end

  def fetch_one(identifier, from, macro \\ "ENVELOPE") do
    fetch(identifier, from, from, macro)
  end

  def fetch(identifier, from, to, macro \\ "ENVELOPE", time_out \\ 50_000) do
    send_to_server(identifier, "FETCH #{from}:#{to} #{macro}", time_out)
  end

  # Helpers
  defp start_imap_connection(hostname, port, conn_fun) do
    identifier = make_identifier(hostname, port)

    with {:ok, _pid} <- ConnectionManager.start_connection(identifier),
         {:ok, greeting} <- conn_fun.(identifier, hostname, port) do
      Logger.debug(greeting)
      {:ok, identifier}
    else
      {:error, {:already_started, _pid}} ->
        {:ok, identifier}

      {:error, _reason} = error ->
        error
    end
  end

  defp send_to_server(identifier, command_string, timeout \\ 5_000) do
    case ClientConnection.send_to_server(identifier, command_string, timeout) do
      {:ok, ast} ->
        ExImapClient.ResponseParser.transform_ast(ast)

      error ->
        error
    end
  end

  defp make_identifier(hostname, port) do
    binary =
      {hostname, port}
      |> inspect()

    {:crypto.hash(:md5, binary), Enum.random(1..1_000_000)}
  end
end
