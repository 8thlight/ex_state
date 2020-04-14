use Mix.Config

config :logger, backends: [:console]
config :logger, :console, level: :warn

config :ex_state, ExState.TestSupport.Repo,
  username: "postgres",
  password: "postgres",
  database: "ex_state_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :ex_state, ecto_repos: [ExState.TestSupport.Repo]
config :ex_state, ExState, repo: ExState.TestSupport.Repo
