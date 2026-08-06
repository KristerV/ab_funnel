defmodule AbFunnel.Migrations.Events do
  @moduledoc """
  The `ab_funnel_events` table: the append-only log every funnel is derived from.
  """
  use Ecto.Migration

  def up do
    create table(:ab_funnel_events, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:visitor_id, :text, null: false)
      add(:event, :text, null: false)
      # Nullable, and no longer written: superseded by `assignments`, kept so events from
      # before experiments existed still read. See `add_assignments/0`.
      add(:variant, :text)
      add(:assignments, :map, null: false, default: fragment("'{}'::jsonb"))
      add(:metadata, :map, null: false, default: fragment("'{}'::jsonb"))

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create(index(:ab_funnel_events, [:visitor_id]))
    create(index(:ab_funnel_events, [:event]))
    create_time_index()
  end

  def down do
    drop_time_index()
    drop_if_exists(index(:ab_funnel_events, [:event]))
    drop_if_exists(index(:ab_funnel_events, [:variant, :event]))
    drop_if_exists(index(:ab_funnel_events, [:visitor_id]))
    drop(table(:ab_funnel_events))
  end

  @doc """
  Separately callable so an existing install can add it without recreating the table.

  Nothing queries by time yet — the report reads everything. It is here because the day
  that changes, the index is a migration against a table that has grown for months, and
  adding it now costs nothing.

  Idempotent because a host app has both paths in its migration history: an install that
  predates this index has a migration calling it directly, while `up/0` above now creates
  it with the table. Replay that history from an empty database — a fresh deploy, a CI
  run — and both fire. The second one has to be a no-op, not a duplicate_table error.
  """
  def create_time_index, do: create_if_not_exists(index(:ab_funnel_events, [:inserted_at]))
  def drop_time_index, do: drop_if_exists(index(:ab_funnel_events, [:inserted_at]))

  @doc """
  Move an existing install from one variant column to per-experiment assignments.

  Three things, all of which have to happen together or writes break:

    * add `assignments`, defaulting to `{}` so existing rows are valid;
    * drop the `NOT NULL` on `variant`, because nothing writes it any more;
    * replace the `(variant, event)` index with one on `event` alone, since grouping is now
      by whatever is inside the jsonb.

  Existing rows keep their `variant` and are attributed at read time — see
  `AbFunnel.Experiments.owning/1`. Nothing is rewritten, so this is safe to run on a live
  table and there is nothing to undo beyond dropping the column again.
  """
  def add_assignments do
    alter table(:ab_funnel_events) do
      add_if_not_exists(:assignments, :map, null: false, default: fragment("'{}'::jsonb"))
      modify(:variant, :text, null: true)
    end

    create_if_not_exists(index(:ab_funnel_events, [:event]))
    drop_if_exists(index(:ab_funnel_events, [:variant, :event]))
  end

  def drop_assignments do
    drop_if_exists(index(:ab_funnel_events, [:event]))

    alter table(:ab_funnel_events) do
      remove_if_exists(:assignments, :map)
    end
  end
end
