defmodule ExState.Examples.VendingMachineTest do
  use ExUnit.Case, async: true

  defmodule VendingMachine do
    use ExState.Definition

    defmodule Context do
      defstruct coins: [], refunded: [], item: nil, vending: nil, vended: nil

      def new do
        %__MODULE__{}
      end

      def put_coin(context, coin) do
        %{context | coins: [coin | context.coins]}
      end

      def paid?(context) do
        Enum.sum(context.coins) >= 100
      end

      def select(context, item) do
        %{context | item: item}
      end

      def vend(context) do
        %{context | vending: context.item, item: nil, coins: []}
      end

      def vended(context) do
        %{context | vended: context.vending, vending: nil}
      end

      def refund(context) do
        %{context | refunded: context.coins, coins: []}
      end
    end

    workflow "vending" do
      initial_state :working

      state :working do
        initial_state :waiting

        on :broken, :out_of_order

        state :waiting do
          on :coin, :calculating
        end

        state :calculating do
          on :_, [:paid, :paying]
        end

        state :paying do
          on :return, :waiting, action: :refund
          on :coin, :calculating
        end

        state :paid do
          on :return, :waiting, action: :refund
          on :select, :vending
        end

        state :vending do
          on_entry :vend
          on :vended, :waiting
          on_exit :vend_complete
        end
      end

      state :out_of_order do
        on :fixed, :working
      end
    end

    def guard_transition(:calculating, :paid, context) do
      if Context.paid?(context) do
        :ok
      else
        {:error, "not paid"}
      end
    end

    def guard_transition(_, _, _), do: :ok

    def refund(context) do
      {:updated, Context.refund(context)}
    end

    def vend(context) do
      {:updated, Context.vend(context)}
    end

    def vend_complete(context) do
      {:updated, Context.vended(context)}
    end

    def add_coin(%{context: context} = execution, coin) do
      execution
      |> put_context(Context.put_coin(context, coin))
      |> transition!(:coin)
      |> execute_actions!()
    end

    def select(%{context: context} = execution, item) do
      execution
      |> put_context(Context.select(context, item))
      |> transition!(:select)
      |> execute_actions!()
    end

    def return(execution) do
      execution
      |> transition!(:return)
      |> execute_actions!()
    end

    def vended(execution) do
      execution
      |> transition!(:vended)
      |> execute_actions!()
    end
  end

  test "calculates payment" do
    %{state: state, context: context} =
      execution =
      VendingMachine.Context.new()
      |> VendingMachine.new()
      |> VendingMachine.add_coin(10)
      |> VendingMachine.add_coin(25)
      |> VendingMachine.add_coin(25)
      |> VendingMachine.add_coin(25)
      |> VendingMachine.add_coin(10)

    assert state.name == "working.paying"
    assert context.coins == [10, 25, 25, 25, 10]

    %{state: state, context: context} =
      execution =
      execution
      |> VendingMachine.add_coin(5)

    assert state.name == "working.paid"
    assert context.coins == [5, 10, 25, 25, 25, 10]

    %{state: state, context: context} =
      execution =
      execution
      |> VendingMachine.select(:a1)

    assert state.name == "working.vending"
    assert context.vending == :a1
    assert context.coins == []

    %{state: state, context: context} =
      execution =
      execution
      |> VendingMachine.vended()

    assert state.name == "working.waiting"
    assert context.vended == :a1
    assert context.coins == []

    %{state: state, context: context} =
      execution =
      execution
      |> VendingMachine.add_coin(10)
      |> VendingMachine.add_coin(25)

    assert state.name == "working.paying"
    assert context.coins == [25, 10]

    %{state: state, context: context} =
      execution =
      execution
      |> VendingMachine.return()

    assert state.name == "working.waiting"
    assert context.coins == []

    %{state: state, context: _context} =
      execution
      |> VendingMachine.transition!(:broken)

    assert state.name == "out_of_order"
  end
end
