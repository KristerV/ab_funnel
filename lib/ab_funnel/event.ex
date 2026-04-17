defmodule AbFunnel.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "ab_funnel_events" do
    field :visitor_id, :string
    field :event, :string
    field :variant, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:visitor_id, :event, :variant, :metadata])
    |> validate_required([:visitor_id, :event, :variant])
  end
end
