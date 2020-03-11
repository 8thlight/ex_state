defmodule ExState.Ecto.Workflow do
  use ExState.Ecto.Model

  alias ExState.Ecto.WorkflowStep
  alias ExState.Ecto.WorkflowParticipant

  schema "workflows" do
    field :name, :string
    field :state, :string
    field :complete?, :boolean, default: false, source: :is_complete
    field :definition, :any, virtual: true
    field :lock_version, :integer, default: 1

    many_to_many :participants, WorkflowParticipant,
      join_through: "workflows_workflow_participants",
      join_keys: [workflow_id: :id, participant_id: :id]

    has_many :steps, WorkflowStep, on_replace: :delete

    timestamps()
  end

  @required_attrs [
    :name,
    :state
  ]

  @optional_attrs [
    :complete?
  ]

  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
    |> optimistic_lock(:lock_version)
  end

  def put_participants(changeset, attrs, transform) do
    put_assoc_maybe(changeset, :participants, attrs, transform)
  end

  def completed_steps(workflow) do
    Enum.filter(workflow.steps, fn step -> step.complete? end)
  end
end
