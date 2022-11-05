defmodule ExImapClient.StreamingTest do
  use ExUnit.Case

  alias ExImapClient.ResponseParser

  test "conversation" do
    final = "final"
    partial = "partial"

    parser = ResponseParser.from_rule_name("test_conversation1")
    sp1 = ResponseParser.streaming_parser(parser, "xx_partial", "xx_final")

    assert {:partial_result, [^partial], _sp3} = sp1.(partial)
    assert {:continue, sp2} = sp1.("par")
    assert {:partial_result, [^partial], sp4} = sp2.("tial")

    assert {:done, {:ok, [^final], "remainder"}} = sp4.("#{final}remainder")

    assert {:done, {:error, _reason}} = sp4.("wrong")

    assert {:partial_result, [^partial], sp7} = sp1.("#{partial}fina")
    assert {:done, {:ok, [^final], "remainder"}} = sp7.("lremainder")

    assert {:partial_result, [^partial], sp7} = sp1.("#{partial}final")
    assert {:done, {:ok, [^final], "remainder"}} = sp7.("remainder")

    assert {:partial_result, [^partial], sp8} = sp1.("partialpartialfinal")
    assert {:partial_result, [^partial], sp9} = sp8.("")
    assert {:done, {:ok, [^final], "remainder"}} = sp9.("remainder")
  end
end
