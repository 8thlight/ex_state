defmodule ExState.Ecto.WorkflowStep do
  use ExState.Ecto.Model

  alias ExState.Ecto.Workflow
  alias ExState.Ecto.WorkflowParticipant

  schema "workflow_steps" do
    field :state, :string
    field :name, :string
    field :order, :integer
    field :decision, :string
    field :complete?, :boolean, default: false, source: :is_complete
    field :completed_at, :utc_datetime_usec
    # TODO
    field :completed_by_id, :integer

    belongs_to :workflow, Workflow

    belongs_to :participant, WorkflowParticipant,
      foreign_key: :participant_id,
      on_replace: :update

    timestamps()
  end

  @required_attrs [
    :state,
    :name,
    :order
  ]

  @optional_attrs [
    :workflow_id,
    :participant_id,
    :complete?,
    :completed_at,
    :completed_by_id
  ]

  def changeset(workflow_step, attrs) do
    workflow_step
    |> cast(attrs, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
  end

  def put_participant(changeset, attrs, transform) do
    put_assoc_maybe(changeset, :participant, attrs, transform)
  end

  def put_completion(changeset, opts) do
    user_id = Keyword.get(opts, :user_id)

    case fetch_change(changeset, :complete?) do
      {:ok, true} ->
        changeset
        |> put_change(:completed_by_id, user_id)
        |> put_change(:completed_at, DateTime.utc_now())

      {:ok, false} ->
        changeset
        |> put_change(:completed_by_id, nil)
        |> put_change(:completed_at, nil)

      :error ->
        changeset
    end
  end
end
