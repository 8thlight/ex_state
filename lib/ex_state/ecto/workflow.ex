defmodule ExState.Ecto.Workflow do
  use ExState.Ecto.Model

  alias ExState.Ecto.WorkflowStep

  schema "workflows" do
    field :name, :string
    field :state, :string
    field :complete?, :boolean, default: false, source: :is_complete
    field :lock_version, :integer, default: 1

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

  def completed_steps(workflow) do
    Enum.filter(workflow.steps, fn step -> step.complete? end)
  end
end
