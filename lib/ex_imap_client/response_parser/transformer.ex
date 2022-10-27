defmodule ExImapClient.ResponseParser.Transformer do
  @moduledoc false

  @result_callback_fun :result_callback_fun
  @stack_callback_fun :stack_callback_fun

  @ci_number :ci_number

  def transform_ast(ast) do
    iterate(ast)
  end

  defp iterate(results \\ [], ast)

  defp iterate(results, []) do
    results
    |> Enum.reverse()
  end

  defp iterate(results, [{@result_callback_fun, fun} | rest]) do
    iterate(fun.(results), rest)
  end

  defp iterate(results, [{@stack_callback_fun, fun} | rest]) do
    {new_results, new_stack} = fun.(results, rest)
    iterate(new_results, new_stack)
  end

  defp iterate(results, [{@ci_number, [number]} | rest]) do
    num =
      case Integer.parse(number) do
        {int, ""} ->
          int

        _ ->
          {float, ""} = Float.parse(number)
          float
      end

    iterate([num | results], rest)
  end

  defp iterate(previous_result, [{:finalResponseCode, kids} | rest]) do
    callback =
      fn new_results ->
        new_results
        |> Enum.reverse()
      end
      |> wrap_result_callback()

    stack_callback =
      fn
        [status | _], stack when status in [:OK, :BAD, :NO] ->
          callback =
            fn last_result ->
              last_result =
                last_result
                |> Enum.reverse()

              [{status, last_result}]
            end
            |> wrap_result_callback()

          {previous_result, stack ++ [callback]}

        _new_results, stack ->
          {previous_result, stack}
      end
      |> wrap_stack_callback()

    iterate(kids ++ [callback, stack_callback | rest])
  end

  defp iterate(results, [{:ci_symbol, [symbol]} | rest]) do
    new_symbol =
      symbol
      |> String.to_atom()

    iterate([new_symbol | results], rest)
  end

  defp iterate(old_results, [{tag, kids} | rest]) do
    callback =
      fn new_results ->
        new_results =
          new_results
          |> Enum.reverse()

        [{tag, new_results} | old_results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(old_results, [list | rest]) when is_list(list) do
    callback =
      fn new_results ->
        new_results =
          new_results
          |> Enum.reverse()

        [new_results | old_results]
      end
      |> wrap_result_callback()

    iterate(list ++ [callback | rest])
  end

  defp iterate(results, [scalar | rest]) do
    iterate([scalar | results], rest)
  end

  defp wrap_result_callback(fun) do
    {@result_callback_fun, fun}
  end

  defp wrap_stack_callback(fun) do
    {@stack_callback_fun, fun}
  end
end
