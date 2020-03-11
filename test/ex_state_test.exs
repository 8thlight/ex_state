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

      {:ok, %{workflow: workflow, subject: subject}} = ExState.create(sale)

      assert subject.workflow_id == workflow.id
      refute workflow.complete?
      assert workflow.state == "pending"

      assert [
               %{name: "buyer"},
               %{name: "seller"}
             ] = Enum.sort_by(workflow.participants, & &1.name)

      assert [
               %{state: "pending", name: "attach_document", complete?: false},
               %{state: "pending", name: "send", complete?: false},
               %{state: "receipt_acknowledged", name: "close", complete?: false},
               %{state: "sent", name: "close", complete?: false},
               %{state: "sent", name: "acknowledge_receipt", complete?: false},
             ] = order_steps(workflow.steps)
    end
  end

  describe "event/3" do
    setup do
      sale = create_sale()

      {:ok, %{workflow: workflow, subject: sale}} = ExState.create(sale)

      [sale: sale, workflow: workflow]
    end

    test "transitions state", %{sale: sale} do
      {:ok, _workflow} = ExState.complete(sale, :attach_document)
      {:ok, _workflow} = ExState.complete(sale, :send)
      {:ok, workflow} = ExState.event(sale, :cancelled)

      assert workflow.complete?
      assert workflow.state == "cancelled"
    end

    test "returns error for unknown transition", %{sale: sale} do
      {:ok, _workflow} = ExState.complete(sale, :attach_document)
      {:ok, _workflow} = ExState.complete(sale, :send)
      {:ok, _workflow} = ExState.complete(sale, :acknowledge_receipt)
      {:error, _} = ExState.event(sale, :cancelled)
      workflow = ExState.get(sale)

      refute workflow.complete?
      assert workflow.state == "receipt_acknowledged"
    end
  end

  describe "complete/3" do
    setup do
      sale = create_sale()

      {:ok, %{workflow: workflow, subject: sale}} = ExState.create(sale)

      [sale: sale, workflow: workflow]
    end

    test "completes a step", %{sale: sale} do
      {:ok, workflow} = ExState.complete(sale, :attach_document)

      refute workflow.complete?
      assert workflow.state == "pending"

      assert [
               %{state: "pending", name: "attach_document", complete?: true},
               %{state: "pending", name: "send", complete?: false},
               %{state: "receipt_acknowledged", name: "close", complete?: false},
               %{state: "sent", name: "close", complete?: false},
               %{state: "sent", name: "acknowledge_receipt", complete?: false},
             ] = order_steps(workflow.steps)
    end
  end
end
