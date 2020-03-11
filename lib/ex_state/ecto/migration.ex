defmodule ExState.Ecto.Migration do
  use Ecto.Migration

  def up do
    create table(:workflows) do
      add(:name, :string, null: false)
      add(:state, :string, null: false)
      add(:is_complete, :boolean, null: false, default: false)
      add(:lock_version, :integer, default: 1)
      timestamps()
    end

    create table(:workflow_participants) do
      add(:name, :string, null: false)
      add(:entity_id, references(:entities, on_delete: :delete_all), null: false)
      timestamps()
    end

    create(unique_index(:workflow_participants, [:entity_id, :name]))

    create table(:workflows_workflow_participants, primary_key: false) do
      add(:workflow_id, references(:workflows, on_delete: :delete_all), null: false)
      add(:participant_id, references(:workflow_participants, on_delete: :delete_all), null: false)
    end

    create(unique_index(:workflows_workflow_participants, [:workflow_id, :participant_id]))

    create table(:workflow_steps) do
      add(:state, :string, null: false)
      add(:name, :string, null: false)
      add(:order, :integer, null: false)
      add(:decision, :string)
      add(:is_complete, :boolean, null: false, default: false)
      add(:completed_at, :utc_datetime_usec)
      add(:workflow_id, references(:workflows, on_delete: :delete_all), null: false)
      add(:completed_by_id, references(:users, on_delete: :nilify_all))
      add(:participant_id, references(:workflow_participants, on_delete: :nilify_all))
      timestamps()
    end

    create(unique_index(:workflow_steps, [:workflow_id, :state, :name]))
    create(index(:workflow_steps, [:participant_id]))
  end
end
