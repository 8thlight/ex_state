defmodule ExState.Ecto.WorkflowStep do
  use ExState.Ecto.Model

  alias ExState.Ecto.Workflow

  schema "workflow_steps" do
    field :state, :string
    field :name, :string
    field :order, :integer
    field :decision, :string
    field :participant, :string
    field :complete?, :boolean, default: false, source: :is_complete
    field :completed_at, :utc_datetime_usec
    field :completed_metadata, :map

    belongs_to :workflow, Workflow

    timestamps()
  end

  @required_attrs [
    :state,
    :name,
    :order
  ]

  @optional_attrs [
    :workflow_id,
    :participant,
    :complete?,
    :completed_at,
    :completed_metadata
  ]

  def changeset(workflow_step, attrs) do
    workflow_step
    |> cast(attrs, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
  end

  def put_completion(changeset, metadata) do
    case fetch_change(changeset, :complete?) do
      {:ok, true} ->
        changeset
        |> put_change(:completed_metadata, metadata)
        |> put_change(:completed_at, DateTime.utc_now())

      {:ok, false} ->
        changeset
        |> put_change(:completed_metadata, nil)
        |> put_change(:completed_at, nil)

      :error ->
        changeset
    end
  end
end
