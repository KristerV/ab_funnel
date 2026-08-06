import Config

config :logger, level: :warning

config :ab_funnel,
  repo: AbFunnel.TestRepo,
  experiments: AbFunnel.TestExperiments,
  # Only read when `:experiments` is unset — the legacy-compatibility tests unset it.
  variants: AbFunnel.TestVariants,
  ecto_repos: [AbFunnel.TestRepo]

config :ab_funnel, AbFunnel.TestRepo,
  database: "ab_funnel_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
