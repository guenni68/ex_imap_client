defmodule ExImapClient.RequestResponseHandlerTest do
  use ExImapClientTestSupport

  alias ExImapClient.RequestResponseHandler, as: Handler
  alias ParserBuilder.Override
  alias ExImapClient.ResponseParser

  test "request response handler" do
    handler0 = Handler.new()

    from1 = "sender1"
    from2 = "sender2"

    response1 = "response1"
    _response2 = "response2"

    {tag1, handler1} =
      handler0
      |> Handler.handle_request(from1, make_ok_result_no_remainder())

    assert "A00001" = tag1

    {tag2, handler2} =
      handler1
      |> Handler.handle_request(from2, make_ok_result_no_remainder())

    assert "A00002" = tag2

    assert {:ok, {:result, result1, _handler3}} = Handler.handle_response(handler2, response1)
    assert {^from1, [override1, ^response1]} = result1
    assert Enum.member?(Override.get_overrides(override1), {"tag", [tag1]})
  end

  test "with remainder" do
    handler0 = Handler.new()
    remainder1 = "remainder1"
    from1 = "sender1"
    from2 = "sender2"
    response1 = "response1"
    response2 = "response2"

    {_tag1, handler1} =
      Handler.handle_request(
        handler0,
        from1,
        make_ok_result_with_remainder(remainder1)
      )

    {_tag2, handler2} =
      Handler.handle_request(
        handler1,
        from2,
        make_ok_result_no_remainder()
      )

    {:ok, {:result, _result1, handler3}} = Handler.handle_response(handler2, response1)
    {:ok, {:result, result2, _handler4}} = Handler.handle_response(handler3, response2)

    assert {^from2, [_override2, parse_result2]} = result2
    assert ^parse_result2 = "#{remainder1}#{response2}"
  end

  test "parsing failed" do
    handler0 = Handler.new()
    from1 = "sender1"
    from2 = "sender2"

    response1 = "response1"
    response2 = "response2"

    {_tag1, handler1} =
      handler0
      |> Handler.handle_request(from1, make_ok_result_no_remainder())

    {_tag2, handler2} =
      handler1
      |> Handler.handle_request(from2, make_error_result())

    {:ok, {:result, {^from1, _result1}, handler3}} =
      Handler.handle_response(
        handler2,
        response1
      )

    {:error, :parse_failed} =
      Handler.handle_response(
        handler3,
        response2
      )
  end

  test "make_continue" do
    input1 = "input1"
    input2 = "input2"
    cont0 = make_continue().("overrides")

    assert {:continue, cont1} = cont0.(input1)
    assert {:done, {:ok, _res1, ""}} = cont1.(input2)
  end

  test "continuation" do
    cont0 = make_continue()
    handler0 = Handler.new()
    from1 = "sender1"
    input1 = "input1"
    input2 = "input2"

    assert {_tag0, handler1} = Handler.handle_request(handler0, from1, cont0)
    assert {:ok, {:continue, handler2}} = Handler.handle_response(handler1, input1)
    assert {:ok, {:result, _result1, _handler3}} = Handler.handle_response(handler2, input2)
  end

  test "conversation" do
    hd1 = Handler.new()
    from = "me"
    partial = "partial"
    final = "final"

    parser = fn overrides ->
      ResponseParser.from_rule_name(overrides, "test_conversation1")
      |> ResponseParser.streaming_parser("xx_partial", "xx_final")
    end

    {_tag, hd2} = Handler.handle_request(hd1, from, parser)

    assert {:ok, {:partial_result, {^from, [^partial]}, hd3}} =
             Handler.handle_response(hd2, partial)

    assert {:ok, {:partial_result, {^from, [^partial]}, hd4}} =
             Handler.handle_response(hd3, partial)

    assert {:ok, {:continue, hd5}} = Handler.handle_response(hd4, "part")

    assert {:ok, {:partial_result, {^from, [^partial]}, hd6}} =
             Handler.handle_response(hd5, "ial")

    assert {:ok, {:continue, hd7}} = Handler.handle_response(hd6, "fi")
    assert {:ok, {:result, {^from, [^final]}, _hd8}} = Handler.handle_response(hd7, "nal")
  end

  defp make_ok_result_no_remainder() do
    fn overrides ->
      fn input ->
        done_ok([overrides, input])
      end
    end
  end

  defp make_ok_result_with_remainder(remainder) do
    fn overrides ->
      fn input ->
        done_ok([overrides, input], remainder)
      end
    end
  end

  defp make_error_result(reason \\ :parse_failed) do
    fn _overrides ->
      fn _input ->
        done_error(reason)
      end
    end
  end

  defp make_continue(continuation \\ fn input -> done_ok(input) end) do
    fn _overrides ->
      fn input1 ->
        {:continue, fn input2 -> continuation.(input1 <> input2) end}
      end
    end
  end

  defp done_ok(result, remainder \\ "") do
    {:done, {:ok, result, remainder}}
  end

  defp done_error(reason) do
    {:done, {:error, reason}}
  end
end
