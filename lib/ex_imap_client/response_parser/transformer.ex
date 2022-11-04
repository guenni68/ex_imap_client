defmodule ExImapClient.ResponseParser.Transformer do
  @moduledoc false

  @result_callback_fun :result_callback_fun
  @stack_callback_fun :stack_callback_fun

  def transform_ast(ast) do
    iterate(ast)
  end

  defp iterate(results \\ [], ast)

  defp iterate(results, []) do
    results
    |> Enum.reverse()
  end

  defp iterate(results, [status]) when status in [:OK, :NO, :BAD] do
    final_results =
      results
      |> Enum.reverse()

    {status, final_results}
  end

  defp iterate(results, [{@result_callback_fun, fun} | rest]) do
    iterate(fun.(results), rest)
  end

  defp iterate(results, [{@stack_callback_fun, fun} | rest]) do
    {new_results, new_stack} = fun.(results, rest)
    iterate(new_results, new_stack)
  end

  defp iterate(results, [{:xx_number, kids} | rest]) do
    callback =
      fn [digits] ->
        case Integer.parse(digits) do
          {integer, ""} ->
            [integer | results]

          _ ->
            {float, ""} = Float.parse(digits)
            [float | results]
        end
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_key_value_map, kids} | rest]) do
    callback =
      fn key_value_pairs ->
        map =
          key_value_pairs
          |> Enum.flat_map(fn
            {k, v} ->
              [{k, v}]

            v ->
              [{:untagged, v}]
          end)
          |> Enum.reduce(Map.new(), fn {k, v}, acc -> acc |> add_key(k, v) end)

        [map | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_key_value, kids} | rest]) do
    callback =
      fn [%{key: [key], value: value}] ->
        [{key, value} | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_date, kids} | rest]) do
    callback =
      fn
        [%{year: [year], month: [month], day: [day]}] ->
          {:ok, date} = Date.new(year, month, day)
          [date | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_date_time_value, kids} | rest]) do
    callback =
      fn
        [%{date: [date], time: [time], offset: [offset]}], stack ->
          {:ok, dt} = DateTime.new(date, time)

          dt =
            dt
            |> DateTime.add(offset, :minute)

          {[dt | results], stack}

        [%{date: [date], time: [time], timezone: [timezone]}], stack ->
          case make_date_time(date, time, timezone) do
            {:ok, dt} ->
              {[dt | results], stack}

            {:error, _reason} = error ->
              {[error], []}
          end

        [%{date: [date], time: [time]}], stack ->
          case NaiveDateTime.new(date, time) do
            {:ok, dt} ->
              {[dt | results], stack}

            {:error, _reason} = error ->
              {[error], []}
          end
      end
      |> wrap_stack_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_microsecond, kids} | rest]) do
    callback =
      fn [float] ->
        ms = (float * 1_000_000) |> trunc()
        [ms | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_time_of_day, kids} | rest]) do
    callback =
      fn [map] ->
        %{
          hour: [hour],
          minute: [minute],
          second: [second],
          microsecond: [microsecond]
        } = make_time_defaults(map)

        {:ok, tod} = make_time(hour, minute, second, microsecond)
        [tod | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_hours_to_minutes, kids} | rest]) do
    callback =
      fn [hours] ->
        [hours * 60 | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_negate, kids} | rest]) do
    callback =
      fn [number] ->
        [number * -1 | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_add, kids} | rest]) do
    callback =
      fn numbers ->
        [Enum.sum(numbers) | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_nil, _kids} | rest]) do
    iterate([nil | results], rest)
  end

  defp iterate(results, [{:xx_symbol, kids} | rest]) do
    callback =
      fn [string] ->
        [string |> String.to_atom() | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
  end

  defp iterate(results, [{:xx_response_ok, []} | rest]) do
    callback =
      fn new_results, new_stack ->
        {new_results, new_stack ++ [:OK]}
      end
      |> wrap_stack_callback()

    iterate(results, [callback | rest])
  end

  defp iterate(results, [{:xx_response_no, []} | rest]) do
    callback =
      fn new_results, new_stack ->
        {new_results, new_stack ++ [:NO]}
      end
      |> wrap_stack_callback()

    iterate(results, [callback | rest])
  end

  defp iterate(results, [{:xx_response_bad, []} | rest]) do
    callback =
      fn new_results, new_stack ->
        {new_results, new_stack ++ [:BAD]}
      end
      |> wrap_stack_callback()

    iterate(results, [callback | rest])
  end

  # TODO implement
  defp iterate(results, [{:xx_offset_map_to_minutes, kids} | rest]) do
    callback =
      fn [offset_map] ->
        %{hour: hour, minute: minute} = make_offset_defaults(offset_map)
        offset = hour * 60 + minute
        [offset | results]
      end
      |> wrap_result_callback()

    iterate(kids ++ [callback | rest])
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

  defp make_time(hour, minute, second, 0) do
    Time.new(hour, minute, second)
  end

  defp make_time(hour, minute, second, microsecond) do
    Time.new(hour, minute, second, microsecond)
  end

  defp make_date_time(date, time, timezone) do
    DateTime.new(date, time, timezone, Tzdata.TimeZoneDatabase)
  end

  defp make_time_defaults(time) do
    %{
      hour: [0],
      minute: [0],
      second: [0],
      microsecond: [0]
    }
    |> Map.merge(time)
  end

  defp make_offset_defaults(offset) do
    %{hour: 0, minute: 0}
    |> Map.merge(offset)
  end

  defp add_key(map, key, values) when is_list(values) do
    Map.merge(map, %{key => values}, fn _k, v2, v1 -> v1 ++ v2 end)
  end

  defp add_key(map, key, value) do
    add_key(map, key, [value])
  end
end
