defmodule ExState.TestSupport.Sale do
  use Ecto.Schema
  use ExState.Ecto.Subject

  import Ecto.Changeset

  alias ExState.TestSupport.SaleWorkflow
  alias ExState.TestSupport.User

  schema "sales" do
    has_workflow SaleWorkflow
    field :product_id, :string
    field :cancelled_at, :utc_datetime
    belongs_to :seller, User
    belongs_to :buyer, User
  end

  def new(params) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(sale, params) do
    sale
    |> cast(params, [
      :product_id,
      :cancelled_at,
      :seller_id,
      :buyer_id,
      :workflow_id
    ])
    |> validate_required([:product_id])
  end
end
