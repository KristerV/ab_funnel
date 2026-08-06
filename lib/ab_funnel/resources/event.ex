defmodule AbFunnel.Resources.Event do
  @moduledoc """
  One thing a visitor did, with the buckets they were in when they did it.

  `assignments` is a map of `experiment => variant`, so an event records every experiment
  the visitor was part of at once. The alternative — a row per experiment — multiplies
  writes by the number of running tests and makes "how many events" meaningless.

  `variant` is the single-experiment column this replaced. Nothing writes it any more; it
  is kept, and nullable, so events recorded before experiments existed still read.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "ab_funnel_events" do
    field(:visitor_id, :string)
    field(:event, :string)
    field(:variant, :string)
    field(:assignments, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:visitor_id, :event, :variant, :assignments, :metadata])
    |> validate_required([:visitor_id, :event])
  end
end
