defmodule AbFunnel.TestRepo.Migrations.AddAbFunnelEventTimeIndex do
  use Ecto.Migration

  def up, do: AbFunnel.Migrations.create_event_time_index()
  def down, do: AbFunnel.Migrations.drop_event_time_index()
end
