defmodule ExImapClient.TransformerTest do
  use ExUnit.Case

  alias ExImapClient.ResponseParser.Transformer

  test "xx_key_value_map" do
    fun = fn values -> Transformer.transform_ast([{:xx_key_value_map, values}]) end

    lst = [
      "ut1",
      {:key1, ["one"]},
      "ut2",
      {:key1, ["two"]}
    ]

    assert [%{key1: ["one", "two"], untagged: ["ut1", "ut2"]}] = fun.(lst)
  end
end
