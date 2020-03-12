defmodule ExStateTest do
  use ExState.TestSupport.EctoCase, async: true

  alias ExState.TestSupport.Sale
  alias ExState.TestSupport.User

  doctest ExState

  def create_sale do
    seller = User.new(%{name: "seller"}) |> Repo.insert!()
    buyer = User.new(%{name: "seller"}) |> Repo.insert!()
    Sale.new(%{
      product_id: "abc123",
      seller_id: seller.id,
      buyer_id: buyer.id
    })
    |> Repo.insert!()
  end

  def order_steps(steps) do
    Enum.sort_by(steps, &"#{&1.state}.#{&1.order}")
  end

  describe "create/1" do
    test "creates a workflow for a workflowable subject" do
      sale = create_sale()

      {:ok, %{subject: sale}} = ExState.create(sale)

      refute sale.workflow.complete?
      assert sale.workflow.state == "pending"

      assert [
               %{name: "buyer"},
               %{name: "seller"}
             ] = Enum.sort_by(sale.workflow.participants, & &1.name)

      assert [
               %{state: "pending", name: "attach_document", complete?: false},
               %{state: "pending", name: "send", complete?: false},
               %{state: "receipt_acknowledged", name: "close", complete?: false},
               %{state: "sent", name: "close", complete?: false},
               %{state: "sent", name: "acknowledge_receipt", complete?: false},
             ] = order_steps(sale.workflow.steps)
    end
  end

  describe "transition/3" do
    setup do
      sale = create_sale()

      {:ok, %{subject: sale}} = ExState.create(sale)

      [sale: sale]
    end

    test "transitions state", %{sale: sale} do
      {:ok, _} = ExState.complete(sale, :attach_document)
      {:ok, _} = ExState.complete(sale, :send)
      {:ok, sale} = ExState.transition(sale, :cancelled)

      assert sale.workflow.complete?
      assert sale.workflow.state == "cancelled"
    end

    test "transitions state through execution module", %{sale: sale} do
      {:ok, sale} =
        sale
        |> ExState.load()
        |> ExState.Execution.complete!(:attach_document)
        |> ExState.Execution.complete!(:send)
        |> ExState.Execution.transition!(:cancelled)
        |> ExState.persist()

      assert sale.workflow.complete?
      assert sale.workflow.state == "cancelled"
    end

    test "returns error for unknown transition", %{sale: sale} do
      {:ok, _} = ExState.complete(sale, :attach_document)
      {:ok, _} = ExState.complete(sale, :send)
      {:ok, _} = ExState.complete(sale, :acknowledge_receipt)
      {:error, _} = ExState.transition(sale, :cancelled)
      workflow = sale |> Ecto.assoc(:workflow) |> Repo.one()

      refute workflow.complete?
      assert workflow.state == "receipt_acknowledged"
    end

    test "returns subject without updates triggered in actions", %{sale: sale} do
      {:ok, sale} = ExState.transition(sale, :cancelled)

      assert sale.cancelled_at == nil
    end
  end

  describe "complete/3" do
    setup do
      sale = create_sale()

      {:ok, %{subject: sale}} = ExState.create(sale)

      [sale: sale]
    end

    test "completes a step", %{sale: sale} do
      {:ok, sale} = ExState.complete(sale, :attach_document)

      refute sale.workflow.complete?
      assert sale.workflow.state == "pending"

      assert [
               %{state: "pending", name: "attach_document", complete?: true},
               %{state: "pending", name: "send", complete?: false},
               %{state: "receipt_acknowledged", name: "close", complete?: false},
               %{state: "sent", name: "close", complete?: false},
               %{state: "sent", name: "acknowledge_receipt", complete?: false},
             ] = order_steps(sale.workflow.steps)
    end

    test "adds user metadata", %{sale: sale} do
      {:ok, sale} = ExState.complete(sale, :attach_document, user_id: "user-1")

      assert sale.workflow.steps
             |> Enum.find(fn s -> s.name == "attach_document" end)
             |> Map.get(:completed_by_id) == "user-1"
    end
  end
end
