defmodule ExImapClient.StructuredResponseTest do
  use ExUnit.Case

  alias ExImapClient.ResponseParser

  def result_from_rule(rule_name) do
    parser =
      rule_name
      |> ResponseParser.from_rule_name_strict()
      |> ResponseParser.finalize()

    fn input ->
      with {:done, {:ok, ast, ""}} <- parser.(input),
           {:ok, result} <- ResponseParser.transform_ast(ast) do
        result
      else
        x ->
          x
      end
    end
  end

  test "only" do
    parser = result_from_rule("response")

    assert {:done, {:error, _reason}} = parser.("+\r\n")
  end
end
