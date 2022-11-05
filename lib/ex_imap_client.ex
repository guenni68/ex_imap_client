defmodule ExImapClient do
  @moduledoc """
  This library offers a feature rich utility to communicate with an IMAP server.

  It returns `fully parsed`, structured responses from the server.

  ## example:

  {:ok, {identifier, greeting_from_server}} = start_connection("your_imap_server")
  login(identifier, "username", "password")

  select(identifier, "inbox")
  examine(identifier)

  fetch(identifier, "1", "1")
  """
  require Logger

  alias ExImapClient.{
    ConnectionManager,
    ClientConnection,
    ResponseParser
  }

  # initialization
  @doc """
  starts an unencrypted connection to `hostname`.
  returns an `identifier` for this connection.
  """
  def start_connection(hostname, port \\ 143) do
    start_connection_tcp(hostname, port)
  end

  @doc """
  starts an unencrypted connection to `hostname`, explicit.
  returns an `identifier` for this connection.
  """
  def start_connection_tcp(hostname, port \\ 143) do
    start_imap_connection(
      hostname,
      port,
      &ClientConnection.connect_tcp/3
    )
  end

  @doc """
  starts an encrypted connection to `hostname`, explicit.
  returns an `identifier` for this connection.
  """
  def start_connection_ssl(hostname, port \\ 993) do
    start_imap_connection(
      hostname,
      port,
      &ClientConnection.connect_ssl/3
    )
  end

  # any state commands
  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def capability(identifier) do
    send_to_server(identifier, "CAPABILITY")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def noop(identifier) do
    send_to_server(identifier, "NOOP")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def logout(identifier) do
    send_to_server(identifier, "LOGOUT")
  end

  # authentication
  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def login(identifier, username, password) do
    send_to_server(identifier, "LOGIN #{username} #{password}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def authenticate_plain(identifier, username, password) do
    with {:ok, _response, token} <- begin_conversation(identifier, "AUTHENTICATE PLAIN") do
      authentication = (<<0>> <> username <> <<0>> <> password) |> Base.encode64()
      continue_conversation(identifier, token, authentication)
    end
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def authenticate_oauth2(identifier, oauth_token) do
    send_to_server(identifier, "AUTHENTICATE XOAUTH2 #{oauth_token}")
  end

  # authenticated state commands
  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def select(identifier, mailbox) do
    send_to_server(identifier, "SELECT #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def examine(identifier, mailbox) do
    send_to_server(identifier, "EXAMINE #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def create(identifier, mailbox) do
    send_to_server(identifier, "CREATE #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def delete(identifier, mailbox) do
    send_to_server(identifier, "DELETE #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def rename(identifier, from, to) do
    send_to_server(identifier, "RENAME #{from} #{to}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def subscribe(identifier, mailbox) do
    send_to_server(identifier, "SUBSCRIBE #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def unsubscribe(identifier, mailbox) do
    send_to_server(identifier, "UNSUBSCRIBE #{mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def list(identifier, from \\ "\"\"", to \\ "\"*\"") do
    send_to_server(identifier, "LIST #{from} #{to}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def lsub(identifier, from \\ "\"\"", to \\ "\"*\"") do
    send_to_server(identifier, "LSUB #{from} #{to}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def status(identifier, mailbox, query \\ "MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN") do
    send_to_server(identifier, "STATUS #{mailbox} (#{query})")
  end

  # TODO offer more options
  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def append(identifier, mailbox, message) do
    send_to_server(identifier, "APPEND #{mailbox} #{message}")
  end

  # selected state commands
  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def check(identifier) do
    send_to_server(identifier, "CHECK")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def close(identifier) do
    send_to_server(identifier, "CLOSE")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def expunge(identifier) do
    send_to_server(identifier, "EXPUNGE")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def search(identifier, criteria \\ "ALL") do
    send_to_server(identifier, "SEARCH #{criteria}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def fetch(identifier, from, to, macro \\ "ENVELOPE", time_out \\ 50_000) do
    send_to_server(identifier, "FETCH #{from}:#{to} #{macro}", time_out)
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def store(identifier, from, to, flags \\ "FLAGS", flag_list) do
    send_to_server(identifier, "STORE #{from}:#{to} #{flags} (#{flag_list})")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def copy(identifier, from, to, destination_mailbox) do
    send_to_server(identifier, "COPY #{from}:#{to} #{destination_mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def uid_fetch(identifier, from_uid, to_uid, macro \\ "ENVELOPE", timeout \\ 50_000) do
    send_to_server(identifier, "UID FETCH #{from_uid}:#{to_uid} #{macro}", timeout)
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def uid_store(identifier, from_uid, to_uid, flags \\ "FLAGS", flag_list) do
    send_to_server(identifier, "UID STORE #{from_uid}:#{to_uid} #{flags} (#{flag_list})")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def uid_copy(identifier, from_uid, to_uid, destination_mailbox) do
    send_to_server(identifier, "UID COPY #{from_uid}:#{to_uid} #{destination_mailbox}")
  end

  @doc """
  requires the connection identifier.
  returns a parsed, structured response from the server.
  """
  def uid_search(identifier, criteria \\ "ALL") do
    send_to_server(identifier, "UID SEARCH #{criteria}")
  end

  # Helpers
  defp start_imap_connection(hostname, port, conn_fun) do
    identifier = make_identifier(hostname, port)

    with {:ok, _pid} <- ConnectionManager.start_connection(identifier),
         {:ok, ast} <- conn_fun.(identifier, hostname, port),
         greeting <- ResponseParser.transform_ast(ast) do
      Logger.debug(greeting)
      {:ok, {identifier, greeting}}
    else
      {:error, _reason} = error ->
        error
    end
  end

  defp send_to_server(identifier, command_string, timeout \\ 5_000) do
    case ClientConnection.send_to_server(identifier, command_string, timeout) do
      {:ok, ast} ->
        ResponseParser.transform_ast(ast)

      error ->
        error
    end
  end

  defp begin_conversation(identifier, message) do
    case ClientConnection.begin_conversation(identifier, message) do
      {:ok, {ast, token}} ->
        {:ok, ResponseParser.transform_ast(ast), token}

      error ->
        error
    end
  end

  defp continue_conversation(identifier, token, message) do
    case ClientConnection.continue_conversation(identifier, token, message) do
      {:ok, ast} ->
        ResponseParser.transform_ast(ast)

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
