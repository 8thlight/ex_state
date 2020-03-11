use Mix.Config

config :ex_state, ExState.TestSupport.Repo,
  username: "postgres",
  password: "postgres",
  database: "ex_state_test",
  hostname: "localhost",
  migration_timestamps: [type: :utc_datetime_usec],
  pool: Ecto.Adapters.SQL.Sandbox
