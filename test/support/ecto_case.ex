defmodule ExState.TestSupport.EctoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias ExState.TestSupport.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ExState.TestSupport.EctoCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ExState.TestSupport.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(ExState.TestSupport.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", format_value(value))
      end)
    end)
  end

  defp format_value({k, v}) do
    "#{to_string(k)} #{to_string(v)}"
  end

  defp format_value(value) do
    to_string(value)
  end
end
