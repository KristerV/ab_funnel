import Config

config :ab_funnel,
  repo: AbFunnel.TestRepo,
  variants: AbFunnel.TestVariants,
  ecto_repos: [AbFunnel.TestRepo]

config :ab_funnel, AbFunnel.TestRepo,
  database: "ab_funnel_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
