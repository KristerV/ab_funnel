defmodule AbFunnel.TestRepo.Migrations.AddAbFunnelEventAssignments do
  use Ecto.Migration

  def up, do: AbFunnel.Migrations.add_event_assignments()
  def down, do: AbFunnel.Migrations.drop_event_assignments()
end
