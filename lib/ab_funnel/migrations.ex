defmodule AbFunnel.Migrations do
  use Ecto.Migration

  def up do
    create table(:ab_funnel_events, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :visitor_id, :text, null: false
      add :event, :text, null: false
      add :variant, :text, null: false
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:ab_funnel_events, [:visitor_id])
    create index(:ab_funnel_events, [:variant, :event])
  end

  def down do
    drop_if_exists index(:ab_funnel_events, [:variant, :event])
    drop_if_exists index(:ab_funnel_events, [:visitor_id])
    drop table(:ab_funnel_events)
  end
end
