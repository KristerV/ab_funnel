defmodule AbFunnel.Migrations.Identities do
  @moduledoc """
  The `ab_funnel_identities` table: which browser belongs to which person.

  Separate from the events migration so an app that installed AbFunnel before identity
  support existed can add just this one.
  """
  use Ecto.Migration

  def up do
    create table(:ab_funnel_identities, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:visitor_id, :text, null: false)
      add(:person_key, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    # One binding per browser — `AbFunnel.Services.Identities.identify/2` upserts on this.
    create(unique_index(:ab_funnel_identities, [:visitor_id]))
    create(index(:ab_funnel_identities, [:person_key]))
  end

  def down do
    drop_if_exists(index(:ab_funnel_identities, [:person_key]))
    drop_if_exists(unique_index(:ab_funnel_identities, [:visitor_id]))
    drop(table(:ab_funnel_identities))
  end
end
