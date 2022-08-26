defmodule ExImap.ClientTest do
  use ExUnit.Case
  doctest ExImap.Client

  test "greets the world" do
    assert ExImap.Client.hello() == :world
  end
end
