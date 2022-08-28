defmodule ExImapClient.RequestResponseHandler do
  @moduledoc false

  alias ParserBuilder.{
    Override
  }

  def new() do
    {0, :queue.new()}
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
    new_queue = :queue.in({from, new_parser})

    {tag, {new_counter, new_queue}}
  end

  def handle_response({counter, queue}, response) do
    with {{:value, {from, parser}}, remaining_queue} <- :queue.out(queue) do
      case parser.(response) do
        {:continue, new_parser} ->
          new_queue = :queue.cons({from, new_parser}, remaining_queue)
          {:ok, {:continue, {counter, new_queue}}}

        {:done, {:ok, result, ""}} ->
          {:ok, {:result, {from, result}, remaining_queue}}

        {:done, {:ok, result, remainder}} ->
          new_queue =
            update_head_of_queue(remaining_queue, fn {from, parser} ->
              {from, fn new_input -> parser.(remainder <> new_input) end}
            end)

          {:ok, {:result, {from, result}, new_queue}}

        {:done, {:error, reason} = error} ->
          error
      end
    end
  end

  # TODO
  defp update_head_of_queue(queue, fun) do
    queue
  end
end
