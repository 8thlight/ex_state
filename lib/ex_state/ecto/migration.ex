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

    create table(:workflow_participants, primary_key: false) do
      add_uuid_primary_key()
      add(:name, :string, null: false)
      add(:entity_id, references_entities(opts))
      timestamps()
    end

    create(unique_index(:workflow_participants, [:entity_id, :name]))

    create table(:workflows_workflow_participants, primary_key: false) do
      add_uuid_primary_key()
      add(:workflow_id, references(:workflows, type: :uuid, on_delete: :delete_all), null: false)
      add(:participant_id, references(:workflow_participants, type: :uuid, on_delete: :delete_all), null: false)
    end

    create(unique_index(:workflows_workflow_participants, [:workflow_id, :participant_id]))

    create table(:workflow_steps, primary_key: false) do
      add_uuid_primary_key()
      add(:state, :string, null: false)
      add(:name, :string, null: false)
      add(:order, :integer, null: false)
      add(:decision, :string)
      add(:is_complete, :boolean, null: false, default: false)
      add(:workflow_id, references(:workflows, type: :uuid, on_delete: :delete_all), null: false)
      add(:participant_id, references(:workflow_participants, type: :uuid, on_delete: :nilify_all))
      add(:completed_at, :utc_datetime_usec)
      add(:completed_by_id, references_users(opts))
      timestamps()
    end

    create(unique_index(:workflow_steps, [:workflow_id, :state, :name]))
    create(index(:workflow_steps, [:participant_id]))
  end

  defp add_uuid_primary_key do
    add(:id, :uuid, primary_key: true, default: {:fragment, "gen_random_uuid()"})
  end

  defp references_users(opts) do
    {table, type} = Keyword.get(opts, :users, {:users, :uuid})
    references(table, type: type, on_delete: :delete_all)
  end

  defp references_entities(opts) do
    {table, type} = Keyword.get(opts, :participants, {:users, :uuid})
    references(table, type: type, on_delete: :delete_all)
  end
end
