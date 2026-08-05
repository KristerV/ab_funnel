defmodule AbFunnel.TestRepo.Migrations.CreateAbFunnelEvents do
  use Ecto.Migration

  # Split from `up/0` so the identities table lands in its own migration below —
  # the same two-step path an app upgrading from an events-only install takes.
  def up, do: AbFunnel.Migrations.create_events()
  def down, do: AbFunnel.Migrations.drop_events()
end
