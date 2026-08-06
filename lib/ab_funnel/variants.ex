defmodule AbFunnel.Variants do
  @moduledoc """
  The original single-experiment API, kept working.

  A module that does `use AbFunnel.Variants` declares one unnamed experiment. It answers
  `experiments/0` as well, so everything downstream — assignment, the report, the
  dashboard — sees the same shape it sees for an app that declares experiments properly,
  and an existing install needs no changes at all.

  New apps should `use AbFunnel.Experiments` instead: one experiment per test, running
  concurrently, each with its own entry event and funnel. See `AbFunnel.Experiments`.
  """

  @callback variants() :: [%{key: atom(), label: String.t(), active: boolean()}]

  @doc """
  The key the single legacy experiment is filed under.

  Also what events written before experiments existed are attributed to, unless the app
  has since declared an experiment that names the same variants — see
  `AbFunnel.Experiments.owning/1`.
  """
  def legacy_key, do: "default"

  defmacro __using__(_opts) do
    quote do
      @behaviour AbFunnel.Variants
      @behaviour AbFunnel.Experiments

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

      @doc """
      This module's variants as the one experiment they have always been.

      Order is inferred and there is no entry event, which is exactly the behaviour this
      module had before experiments existed. Override it — or move to
      `use AbFunnel.Experiments` — to gain either.
      """
      def experiments do
        [
          %{
            key: AbFunnel.Variants.legacy_key(),
            label: "Experiment",
            variants: Enum.map(variants(), &Map.take(&1, [:key, :label, :active]))
          }
        ]
      end

      defoverridable experiments: 0
    end
  end
end
