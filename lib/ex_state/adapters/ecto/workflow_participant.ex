defmodule ExState.Ecto.WorkflowParticipant do
  use ExState.Ecto.Model

  alias ExState.Ecto.WorkflowStep

  # TODO
  alias MyApp.Entities.Entity

  schema "workflow_participants" do
    field :name, :string
    belongs_to :entity, Entity
    has_many :steps, WorkflowStep, foreign_key: :participant_id
    timestamps()
  end

  @required_attrs [
    :name,
    :entity_id
  ]

  @optional_attrs []

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
    |> unique_constraint(:name, name: "workflow_participants_entity_id_name_index")
  end
end
