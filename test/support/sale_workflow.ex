defmodule ExState.TestSupport.SaleWorkflow do
  use ExState.Definition

  import Ecto.Query

  alias ExState.TestSupport.Repo
  alias ExState.TestSupport.Sale

  workflow "sale" do
    subject :sale, Sale

    participant :seller
    participant :buyer

    initial_state :pending

    state :pending do
      step :attach_document, participant: :seller
      step :send, participant: :seller
      on :cancelled, :cancelled
      on :document_replaced, :_
      on_completed :send, :sent
    end

    state :sent do
      parallel do
        step :acknowledge_receipt, participant: :buyer
        step :close, participant: :seller
      end

      on :cancelled, :cancelled
      on :document_replaced, :pending
      on_completed :acknowledge_receipt, :receipt_acknowledged
      on_completed :close, :closed
    end

    state :receipt_acknowledged do
      step :close, participant: :seller
      on_completed :close, :closed
    end

    state :closed

    state :cancelled do
      on_entry :update_cancelled_at
    end
  end

  def participant(sale, :seller) do
    sale
    |> Ecto.assoc(:seller)
    |> select([u], u.name)
    |> Repo.one()
  end

  def participant(sale, :buyer) do
    sale
    |> Ecto.assoc(:buyer)
    |> select([u], u.name)
    |> Repo.one()
  end

  def use_step?(_sale, _step), do: true

  def guard_transition(_sale, _from, _to), do: :ok

  def update_cancelled_at(sale) do
    sale
    |> Sale.changeset(%{cancelled_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
