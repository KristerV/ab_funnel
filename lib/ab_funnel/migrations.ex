defmodule AbFunnel.Migrations do
  @moduledoc """
  What a host app calls from its own migration. One table per module under
  `AbFunnel.Migrations.*`; this is the entry point that names them together.
  """

  alias AbFunnel.Migrations.Events
  alias AbFunnel.Migrations.Identities

  @doc """
  Everything AbFunnel needs, for a fresh install.

  An app that already ran an earlier version has the events table and needs only
  `create_identities/0` in a new migration of its own.
  """
  def up do
    Events.up()
    Identities.up()
  end

  def down do
    Identities.down()
    Events.down()
  end

  def create_events, do: Events.up()
  def drop_events, do: Events.down()

  def create_identities, do: Identities.up()
  def drop_identities, do: Identities.down()

  def create_event_time_index, do: Events.create_time_index()
  def drop_event_time_index, do: Events.drop_time_index()

  def add_event_assignments, do: Events.add_assignments()
  def drop_event_assignments, do: Events.drop_assignments()
end
