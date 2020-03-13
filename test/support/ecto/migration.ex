defmodule ExState.TestSupport.Migration do
  use Ecto.Migration

  def up do
    create table(:users) do
      add(:name, :string, null: false)
    end

    ExState.Ecto.Migration.up(
      install_pgcrypto: true,
      users: {:users, :bigint},
      participants: {:users, :bigint}
    )

    create table(:sales) do
      add(:product_id, :string, null: false)
      add(:cancelled_at, :utc_datetime)
      add(:seller_id, references(:users))
      add(:buyer_id, references(:users))
      add(:workflow_id, references(:workflows, type: :uuid))
    end
  end
end
