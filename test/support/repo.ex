defmodule AbFunnel.TestRepo do
  use Ecto.Repo,
    otp_app: :ab_funnel,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :priv, "priv/repo")}
  end
end
