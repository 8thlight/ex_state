use Mix.Config

config :logger, backends: [:console]
config :logger, :console, level: :warn

# Test Support Repos
config :ex_state, ExState.TestSupport.Repo,
  username: "postgres",
  password: "postgres",
  database: "ex_state_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :ex_state, ecto_repos: [ExState.TestSupport.Repo]

# ExState's Repo
config :ex_state, repo: ExState.TestSupport.Repo
