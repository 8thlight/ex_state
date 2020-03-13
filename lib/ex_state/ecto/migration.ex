defmodule ExState.Ecto.Migration do
  use Ecto.Migration

  def up(opts \\ []) do
    if Keyword.get(opts, :install_pgcrypto, false) do
      execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    end

    create table(:workflows, primary_key: false) do
      add_uuid_primary_key()
      add(:name, :string, null: false)
      add(:state, :string, null: false)
      add(:is_complete, :boolean, null: false, default: false)
      add(:lock_version, :integer, default: 1)
      timestamps()
    end

    create table(:workflow_steps, primary_key: false) do
      add_uuid_primary_key()
      add(:state, :string, null: false)
      add(:name, :string, null: false)
      add(:order, :integer, null: false)
      add(:decision, :string)
      add(:participant, :string)
      add(:is_complete, :boolean, null: false, default: false)
      add(:workflow_id, references(:workflows, type: :uuid, on_delete: :delete_all), null: false)
      add(:completed_at, :utc_datetime_usec)
      add(:completed_metadata, :map)
      timestamps()
    end

    create(unique_index(:workflow_steps, [:workflow_id, :state, :name]))
    create(index(:workflow_steps, [:participant]))
  end

  defp add_uuid_primary_key do
    add(:id, :uuid, primary_key: true, default: {:fragment, "gen_random_uuid()"})
  end
end
