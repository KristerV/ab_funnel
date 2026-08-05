defmodule AbFunnel.FakeCiString do
  @moduledoc """
  Stands in for `Ash.CiString` and friends: a wrapper an app might hold in its `email`
  field, which only produces the address through `String.Chars`.
  """
  defstruct [:value]

  defimpl String.Chars do
    def to_string(%{value: value}), do: value
  end
end
