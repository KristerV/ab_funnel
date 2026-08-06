defmodule AbFunnel.Experiment do
  @moduledoc """
  One experiment, normalised.

  The app declares experiments as loose maps; everything downstream works on this struct,
  where keys are strings (because that is what the events table holds) and every optional
  field has been filled in.

  Build one with `AbFunnel.Experiments.normalise/1` rather than by hand.
  """

  @type variant :: %{
          key: String.t(),
          label: String.t(),
          weight: non_neg_integer(),
          control?: boolean()
        }

  @type t :: %__MODULE__{
          key: String.t(),
          label: String.t(),
          variants: [variant()],
          entry: String.t() | nil,
          goal: String.t() | nil,
          steps: nil | [String.t()] | {module(), atom(), 1} | (String.t() -> [String.t()]),
          since: DateTime.t() | nil,
          mde: float(),
          active?: boolean()
        }

  defstruct key: nil,
            label: nil,
            variants: [],
            entry: nil,
            goal: nil,
            steps: nil,
            since: nil,
            mde: 0.2,
            active?: true

  @doc "The variant every other arm is measured against."
  def control(%__MODULE__{variants: variants}) do
    Enum.find(variants, & &1.control?) || List.first(variants)
  end

  @doc "Whether this experiment declares a variant by that name, retired or not."
  def known?(%__MODULE__{variants: variants}, key) when is_binary(key) do
    Enum.any?(variants, &(&1.key == key))
  end

  @doc "The variants a new visitor can still be assigned to."
  def assignable(%__MODULE__{variants: variants}) do
    Enum.filter(variants, &(&1.weight > 0))
  end

  @doc "The declared label for a variant, falling back to the raw key."
  def variant_label(%__MODULE__{variants: variants}, key) do
    case Enum.find(variants, &(&1.key == key)) do
      %{label: label} -> label
      nil -> key
    end
  end
end
