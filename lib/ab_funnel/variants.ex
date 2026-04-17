defmodule AbFunnel.Variants do
  @callback variants() :: [%{key: atom(), label: String.t(), active: boolean()}]

  defmacro __using__(_opts) do
    quote do
      @behaviour AbFunnel.Variants

      def all, do: variants()

      def keys do
        variants()
        |> Enum.filter(& &1.active)
        |> Enum.map(& &1.key)
      end

      def name(key) when is_atom(key) do
        case Enum.find(variants(), &(&1.key == key)) do
          %{label: label} -> label
          nil -> to_string(key)
        end
      end

      def name(key) when is_binary(key) do
        name(String.to_existing_atom(key))
      rescue
        ArgumentError -> key
      end

      def random_key, do: Enum.random(keys())
    end
  end
end
