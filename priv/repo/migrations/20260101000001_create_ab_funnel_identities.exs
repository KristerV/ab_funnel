defmodule AbFunnel.TestRepo.Migrations.CreateAbFunnelIdentities do
  use Ecto.Migration

  def up, do: AbFunnel.Migrations.create_identities()
  def down, do: AbFunnel.Migrations.drop_identities()
end
