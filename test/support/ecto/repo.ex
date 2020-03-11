defmodule ExState.TestSupport.Repo do
  use Ecto.Repo,
    otp_app: :ex_state,
    adapter: Ecto.Adapters.Postgres
end
