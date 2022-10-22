defmodule ExImapClientTestSupport do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case
      import unquote(__MODULE__)
    end
  end
end
