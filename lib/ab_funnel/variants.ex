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

      def random_key do
        case keys() do
          [] ->
            raise """
            #{inspect(__MODULE__)} has no active variants, so there is nothing to assign \
            a new visitor to. At least one variant needs `active: true`.\
            """

          keys ->
            Enum.random(keys)
        end
      end

      @doc """
      Whether `key` names a variant this module declares, active or not.

      Inactive counts as known: a visitor assigned before a variant was retired keeps it.
      """
      def known?(key) when is_binary(key) do
        Enum.any?(variants(), &(Atom.to_string(&1.key) == key))
      end

      def known?(key) when is_atom(key), do: Enum.any?(variants(), &(&1.key == key))
    end
  end
end
