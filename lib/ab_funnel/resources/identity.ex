defmodule AbFunnel.Resources.Identity do
  @moduledoc """
  Binds one browser (`visitor_id`) to one person (`person_key`).

  A visitor id only ever identifies a browser — a second device, a second browser, or a
  cleared cookie jar is a different visitor. That is fine until a funnel crosses an
  authentication boundary, at which point the same human shows up as two visitors and
  neither of them completes the funnel.

  A row here says "these events belong to the same person". Nothing rewrites the events
  themselves; `AbFunnel.AdminLive` resolves visitor ids through this table at read time,
  which is what makes identifying a visitor retroactive over everything that browser
  already did.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "ab_funnel_identities" do
    field(:visitor_id, :string)
    field(:person_key, :string)

    timestamps()
  end

  def changeset(identity \\ %__MODULE__{}, attrs) do
    identity
    |> cast(attrs, [:visitor_id, :person_key])
    |> validate_required([:visitor_id, :person_key])
    |> unique_constraint(:visitor_id)
  end
end
