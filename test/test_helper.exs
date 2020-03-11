{:ok, _} = ExState.TestSupport.Repo.start_link()
_ = Ecto.Migrator.up(ExState.TestSupport.Repo, 1, ExState.TestSupport.Migration)
ExUnit.start()
