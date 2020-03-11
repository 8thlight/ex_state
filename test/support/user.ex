defmodule ExState.TestSupport.User do
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :name, :string
  end

  def new(params) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(sale, params) do
    sale
    |> cast(params, [:name])
    |> validate_required([:name])
  end
end
