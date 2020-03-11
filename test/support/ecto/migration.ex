defmodule ExState.TestSupport.Migration do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    ExState.Ecto.Migration.up()

    create table(:users) do
      add(:name, :string, null: false)
    end

    create table(:sales) do
      add(:product_id, :string, null: false)
      add(:seller_id, references(:users))
      add(:buyer_id, references(:users))
      add(:workflow_id, references(:workflows, type: :uuid))
    end
  end
end
