defmodule ExImapClient.Data do
  @moduledoc false

  def new(hostname, port, username, password) do
    %{
      hostname: hostname,
      port: port,
      username: username,
      password: password,
      requests: %{}
    }
  end

  def get_hostname(data) do
    data
    |> Map.get(:hostname)
  end

  def get_port(data) do
    data
    |> Map.get(:port)
  end

  def add_request(data, key, from) do
    data
  end

  def each_request(data, fun) do
    data
    |> Map.get(:requests)
    |> Enum.each(fun)
  end
end
