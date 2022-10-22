defmodule ExImapClient.RequestResponseHandler do
  @moduledoc false

  alias ParserBuilder.{
    Override
  }

  def new(counter \\ 0, queue \\ :queue.new())

  def new(counter, queue) do
    {counter, queue}
  end

  def handle_request({counter, queue}, from, parser) do
    new_counter = counter + 1

    tag =
      new_counter
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
      |> (fn x -> "A#{x}" end).()

    overrides =
      Override.new()
      |> Override.add_rule_override("tag", tag)

    new_parser = parser.(overrides)
    new_queue = :queue.in({from, new_parser}, queue)

    {tag, new(new_counter, new_queue)}
  end

  def handle_response({counter, queue}, response) do
    with {{:value, {from, parser}}, remaining_queue} <- :queue.out(queue) do
      case parser.(response) do
        {:continue, new_parser} ->
          new_queue = :queue.cons({from, new_parser}, remaining_queue)
          {:ok, {:continue, new(counter, new_queue)}}

        {:done, {:ok, result, ""}} ->
          {:ok, {:result, {from, result}, new(counter, remaining_queue)}}

        {:done, {:ok, result, remainder}} ->
          fun = fn {from, parser} ->
            {from, fn new_input -> parser.(remainder <> new_input) end}
          end

          case update_head_of_queue(remaining_queue, fun) do
            {:ok, new_queue} ->
              {:ok, {:result, {from, result}, new(counter, new_queue)}}

            {:error, _reason} = error ->
              error
          end

        {:done, {:error, _reason} = error} ->
          error
      end
    else
      _ ->
        {:error, :empty_queue}
    end
  end

  def get_senders({_count, queue}) do
    queue
    |> :queue.to_list()
    |> Enum.map(fn {from, _parser} -> from end)
  end

  defp update_head_of_queue(queue, fun) do
    with {{:value, value}, new_queue} <- :queue.out(queue) do
      {:ok, :queue.cons(fun.(value), new_queue)}
    else
      reason ->
        {:error, reason}
    end
  end
end
