defmodule ExState.DefinitionTest do
  use ExUnit.Case, async: true

  defmodule SimpleWorkflow do
    use ExState.Definition

    workflow "simple" do
      subject :anything

      initial_state :a

      state :a do
        on :go_to_b, :b
      end

      state :b
      state :c
    end
  end

  defmodule Message do
    defstruct review?: true, confirm?: true, sender_id: nil, recipient_id: nil, feedback: nil
  end

  defmodule SendWorkflow do
    use ExState.Definition

    workflow "send" do
      subject :message, Message

      participant :sender
      participant :recipient

      initial_state :pending

      state :pending do
        on_entry :notify_started
        on_exit :log_stuff

        initial_state :sending

        on :cancel, :cancelled
        on :ignore, :ignored

        state :sending do
          step :prepare, participant: :sender, repeatable: true
          step :review, participant: :sender, repeatable: true
          step :send, participant: :sender
          on_completed :send, :sent
        end

        state :sent do
          step :confirm, participant: :recipient
          on_completed :confirm, {:<, :confirmed}
        end
      end

      state :confirmed do
        initial_state :deciding

        state :deciding do
          step :decide
          on_decision :decide, :good, {:<, :good}
          on_decision :decide, :bad, {:<, :bad}
        end
      end

      state :cancelled do
        on_entry :notify_cancelled
        on :cancel, :_
      end

      state :ignored do
        step :remind, repeatable: true
      end

      state :good do
        final
      end

      state :bad do
        final
      end
    end

    def participant(m, :sender), do: m.sender_id
    def participant(m, :recipient), do: m.recipient_id

    def use_step?(m, :review), do: m.review?
    def use_step?(m, :confirm), do: m.confirm?
    def use_step?(_, _), do: true

    def notify_started(_), do: {:ok, "notified started"}
    def notify_cancelled(_), do: {:ok, "notified cancelled"}
    def log_stuff(_), do: :ok
  end

  describe "name/0" do
    test "defines name" do
      assert SimpleWorkflow.name() == "simple"
    end
  end

  describe "subject/0" do
    test "defines subject type" do
      assert SimpleWorkflow.subject() == :anything
    end
  end

  describe "initial_state" do
    test "defines initial state" do
      assert SimpleWorkflow.initial_state() == "a"
    end

    test "transitions to initial states" do
      assert SendWorkflow.new(%Message{})
             |> Map.get(:state)
             |> Map.get(:name) == "pending.sending"
    end
  end

  describe "state" do
    test "defines simple state" do
      assert SimpleWorkflow.state(:b).name == "b"
    end

    test "defines sub states" do
      assert SendWorkflow.state(:pending).initial_state == "pending.sending"
      assert SendWorkflow.state(:pending, :sending).name == "pending.sending"
      assert SendWorkflow.state(:confirmed, :deciding).name == "confirmed.deciding"
    end

    test "defines state with steps" do
      assert SendWorkflow.state(:pending, :sending).steps
             |> Enum.sort_by(& &1.order)
             |> Enum.map(& &1.name) == [
               "prepare",
               "review",
               "send"
             ]
    end
  end

  describe "transition/2" do
    test "defines event transition" do
      assert SimpleWorkflow.continue("a")
             |> SimpleWorkflow.transition_maybe(:go_to_b)
             |> Map.get(:state)
             |> Map.get(:name) == "b"

      assert SimpleWorkflow.continue("b")
             |> SimpleWorkflow.transition_maybe(:go_to_b)
             |> Map.get(:state)
             |> Map.get(:name) == "b"

      assert SimpleWorkflow.continue("c")
             |> SimpleWorkflow.transition_maybe(:go_to_b)
             |> Map.get(:state)
             |> Map.get(:name) == "c"
    end

    test "defines completed step transition" do
      assert SendWorkflow.continue("pending.sending", %Message{})
             |> SendWorkflow.transition_maybe({:completed, :send})
             |> Map.get(:state)
             |> Map.get(:name) == "pending.sent"
    end

    test "defines decision transition" do
      assert SendWorkflow.continue("confirmed.deciding", %Message{})
             |> SendWorkflow.transition_maybe({:decision, :decide, :good})
             |> Map.get(:state)
             |> Map.get(:name) == "good"

      assert SendWorkflow.continue("confirmed.deciding", %Message{})
             |> SendWorkflow.transition_maybe({:decision, :decide, :bad})
             |> Map.get(:state)
             |> Map.get(:name) == "bad"
    end

    test "transitions to initial state" do
      assert SendWorkflow.new(%Message{})
             |> Map.get(:state)
             |> Map.get(:name) == "pending.sending"

      assert SendWorkflow.new(%Message{})
             |> SendWorkflow.transition_maybe({:completed, :send})
             |> SendWorkflow.transition_maybe({:completed, :confirm})
             |> Map.get(:state)
             |> Map.get(:name) == "confirmed.deciding"
    end

    test "defines parent state transition" do
      assert SendWorkflow.continue("pending.sent", %Message{})
             |> SendWorkflow.transition_maybe({:completed, :confirm})
             |> Map.get(:state)
             |> Map.get(:name) == "confirmed.deciding"
    end

    test "completes a workflow" do
      execution =
        SendWorkflow.new(%Message{})
        |> SendWorkflow.transition_maybe({:completed, :send})
        |> SendWorkflow.transition_maybe({:completed, :confirm})
        |> SendWorkflow.transition_maybe({:decision, :decide, :good})

      assert execution.state.name == "good"
      assert SendWorkflow.complete?(execution)
    end

    test "passes event to parent states" do
      execution =
        SendWorkflow.new(%Message{})
        |> SendWorkflow.transition_maybe(:cancel)

      assert execution.state.name == "cancelled"
    end

    test "ignores invalid transitions" do
      execution =
        SendWorkflow.new(%Message{})
        |> SendWorkflow.transition_maybe({:completed, :prepare})
        |> SendWorkflow.transition_maybe({:completed, :review})
        |> SendWorkflow.transition_maybe({:completed, :send})
        |> SendWorkflow.transition_maybe({:completed, :confirm})
        |> SendWorkflow.transition_maybe(:cancel)
        |> SendWorkflow.transition_maybe({:decision, :decide, :good})

      assert execution.state.name == "good"
    end

    test "allows defined internal transitions" do
      assert {:ok, _} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.transition!(:cancel)
               |> SendWorkflow.transition(:cancel)
    end

    test "returns triggered actions" do
      assert [
               :notify_cancelled,
               :log_stuff,
               :notify_started
             ] =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.transition_maybe(:cancel)
               |> Map.get(:actions)

      assert [
               :log_stuff,
               :notify_started
             ] =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.transition_maybe({:completed, :send})
               |> SendWorkflow.transition_maybe({:completed, :confirm})
               |> Map.get(:actions)
    end

    test "continue does not trigger entry actions" do
      assert [
               :notify_cancelled,
               :log_stuff
             ] =
               SendWorkflow.continue("pending", %Message{})
               |> SendWorkflow.transition_maybe(:cancel)
               |> Map.get(:actions)

      assert [
               :log_stuff,
               :notify_started
             ] =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.transition_maybe({:completed, :send})
               |> SendWorkflow.transition_maybe({:completed, :confirm})
               |> Map.get(:actions)
    end

    test "executes triggered actions" do
      {:ok, execution, results} =
        SendWorkflow.new(%Message{})
        |> SendWorkflow.transition_maybe(:cancel)
        |> SendWorkflow.execute_actions()

      assert execution.state.name == "cancelled"

      assert results == %{
               notify_started: "notified started",
               notify_cancelled: "notified cancelled"
             }
    end
  end

  describe "will_transition/2" do
    test "determines valid transitions" do
      execution = SendWorkflow.new(%Message{})

      assert SendWorkflow.will_transition?(execution, {:completed, :send})
      refute SendWorkflow.will_transition?(execution, {:completed, :confirm})
    end
  end

  describe "complete/2" do
    test "complete step returns ok" do
      assert {:ok, %{state: %{name: "pending.sending"}} = execution} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.complete(:prepare)

      assert {:ok, %{state: %{name: "pending.sending"}} = execution} =
               execution
               |> SendWorkflow.complete(:review)

      assert {:ok, %{state: %{name: "pending.sent"}} = execution} =
               execution
               |> SendWorkflow.complete(:send)

      assert {:error, _, %{state: %{name: "pending.sent"}}} =
               execution
               |> SendWorkflow.complete(:send)
    end

    test "complete step returns ok for repeatable step" do
      assert {:ok, %{state: %{name: "pending.sending"}} = execution} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.complete(:prepare)

      assert {:ok, %{state: %{name: "pending.sending"}}} =
               execution
               |> SendWorkflow.complete(:prepare)
    end

    test "completes step returns ok for repeatable last step" do
      assert {:ok, %{state: %{name: "ignored"}} = execution} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.transition_maybe(:ignore)
               |> SendWorkflow.complete(:remind)

      assert {:ok, %{state: %{name: "ignored"}}} =
               execution
               |> SendWorkflow.complete(:remind)
    end

    test "complete step returns error for repeatable step out of order" do
      assert {:error, _, %{state: %{name: "pending.sending"}}} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.complete(:review)
    end

    test "complete step accounts for unused steps" do
      assert {:ok, %{state: %{name: "pending.sending"}} = execution} =
               SendWorkflow.new(%Message{review?: false})
               |> SendWorkflow.complete(:prepare)

      assert {:error, _, %{state: %{name: "pending.sending"}} = execution} =
               execution
               |> SendWorkflow.complete(:review)

      assert {:ok, %{state: %{name: "pending.sent"}} = execution} =
               execution
               |> SendWorkflow.complete(:send)
    end

    test "complete step returns error" do
      assert {:error, _, %{state: %{name: "pending.sending"}}} =
               SendWorkflow.new(%Message{})
               |> SendWorkflow.complete(:send)
    end
  end

  defmodule ParallelWorkflow do
    use ExState.Definition

    workflow "rate" do
      subject :message, Message

      initial_state :not_done

      state :not_done do
        parallel do
          step :do_one_thing
          step :do_another_thing
        end

        step :do_last_thing
        on_completed :do_last_thing, :done
      end

      state :done
    end
  end

  describe "parallel steps" do
    test "completes steps in any order" do
      assert {:ok, %{state: %{name: "not_done"}} = execution} =
               ParallelWorkflow.new(%Message{})
               |> ParallelWorkflow.complete(:do_another_thing)

      assert {:error, reason, %{state: %{name: "not_done"}} = execution} =
               execution
               |> ParallelWorkflow.complete(:do_last_thing)

      assert reason == "next step is: do_one_thing"

      assert {:ok, %{state: %{name: "not_done"}} = execution} =
               execution
               |> ParallelWorkflow.complete(:do_one_thing)

      assert {:ok, %{state: %{name: "done"}} = execution} =
               execution
               |> ParallelWorkflow.complete(:do_last_thing)
    end
  end

  describe "with_completed/2" do
    test "loads state with completed steps" do
      assert {:ok, %{state: %{name: "pending.sent"}}} =
               SendWorkflow.continue("pending.sending", %Message{})
               |> SendWorkflow.with_completed("pending.sending", "prepare")
               |> SendWorkflow.with_completed("pending.sending", "review")
               |> SendWorkflow.complete(:send)
    end
  end

  defmodule DecisionWorkflow do
    use ExState.Definition

    workflow "rate" do
      subject :message, Message

      initial_state :not_rated

      state :not_rated do
        step :rate
        on_decision :rate, :good, :done
        on_decision :rate, :bad, :feedback
      end

      state :feedback do
        repeatable :rate
        on_decision :rate, :good, :done
        on_decision :rate, :bad, :_, reset: false

        step :confirm_rating
        step :provide_feedback
        on_completed :provide_feedback, :done
      end

      state :done
    end

    def guard_transition(message, _, :done) do
      if message.feedback == "too short" do
        {:error, "feedback is too short to be done"}
      else
        :ok
      end
    end

    def guard_transition(_, _, _), do: :ok
  end

  describe "decision/3" do
    test "transitions to new state" do
      assert {:ok, %{state: %{name: "done"}}} =
               DecisionWorkflow.new(%Message{})
               |> DecisionWorkflow.decision(:rate, :good)
    end

    test "returns error for unknown decision" do
      assert {:error, _, _} =
               DecisionWorkflow.new(%Message{})
               |> DecisionWorkflow.decision(:rate, :something_else)
    end

    test "returns error for guarded transition" do
      assert {:error, reason, _} =
               DecisionWorkflow.continue("feedback", %Message{feedback: "too short"})
               |> DecisionWorkflow.with_completed("feedback", "confirm_rating")
               |> DecisionWorkflow.complete(:provide_feedback)

      assert reason == "feedback is too short to be done"
    end

    test "handles repeatable decision" do
      assert {:ok, %{state: %{name: "feedback"}} = execution} =
               DecisionWorkflow.new(%Message{})
               |> DecisionWorkflow.decision(:rate, :bad)

      assert {:ok, %{state: %{name: "feedback"}} = execution} =
               execution
               |> DecisionWorkflow.decision(:rate, :bad)

      assert {:ok, %{state: %{name: "feedback"}} = execution} =
               execution
               |> DecisionWorkflow.complete(:confirm_rating)

      assert {:ok, %{state: %{name: "feedback"}} = execution} =
               execution
               |> DecisionWorkflow.decision(:rate, :bad)

      assert Enum.find(execution.state.steps, fn s -> s.name == "confirm_rating" end).complete?

      assert {:ok, %{state: %{name: "done"}} = execution} =
               execution
               |> DecisionWorkflow.decision(:rate, :good)
    end
  end

  describe "dump/1" do
    test "returns workflow data" do
      message = %Message{confirm?: true, sender_id: 1, recipient_id: 2}

      assert SendWorkflow.new(message) |> SendWorkflow.dump() == %{
               name: "send",
               complete?: false,
               state: "pending.sending",
               subject: {:message, message},
               participants: [
                 "recipient",
                 "sender",
               ],
               steps: [
                 %{
                   name: "decide",
                   order: 1,
                   participant: nil,
                   state: "confirmed.deciding",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "remind",
                   order: 1,
                   participant: nil,
                   state: "ignored",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "send",
                   order: 3,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "review",
                   order: 2,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "prepare",
                   order: 1,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "confirm",
                   order: 1,
                   participant: "recipient",
                   state: "pending.sent",
                   complete?: false,
                   decision: nil
                 }
               ]
             }
    end

    test "excludes unused steps" do
      confirmed_message = %Message{confirm?: false, sender_id: 1, recipient_id: 2}

      assert SendWorkflow.new(confirmed_message) |> SendWorkflow.dump() == %{
               name: "send",
               complete?: false,
               state: "pending.sending",
               subject: {:message, confirmed_message},
               participants: [
                 "recipient",
                 "sender",
               ],
               steps: [
                 %{
                   name: "decide",
                   order: 1,
                   participant: nil,
                   state: "confirmed.deciding",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "remind",
                   order: 1,
                   participant: nil,
                   state: "ignored",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "send",
                   order: 3,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "review",
                   order: 2,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "prepare",
                   order: 1,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: false,
                   decision: nil
                 }
               ]
             }
    end

    test "includes completed steps from previous states" do
      message = %Message{confirm?: true, sender_id: 1, recipient_id: 2}

      assert SendWorkflow.continue("confirmed.deciding", message)
             |> SendWorkflow.with_completed("pending.sending", "prepare")
             |> SendWorkflow.with_completed("pending.sending", "review")
             |> SendWorkflow.with_completed("pending.sending", "send")
             |> SendWorkflow.dump() == %{
               name: "send",
               complete?: false,
               state: "confirmed.deciding",
               subject: {:message, message},
               participants: [
                 "recipient",
                 "sender",
               ],
               steps: [
                 %{
                   name: "decide",
                   order: 1,
                   participant: nil,
                   state: "confirmed.deciding",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "remind",
                   order: 1,
                   participant: nil,
                   state: "ignored",
                   complete?: false,
                   decision: nil
                 },
                 %{
                   name: "send",
                   order: 3,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: true,
                   decision: nil
                 },
                 %{
                   name: "review",
                   order: 2,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: true,
                   decision: nil
                 },
                 %{
                   name: "prepare",
                   order: 1,
                   participant: "sender",
                   state: "pending.sending",
                   complete?: true,
                   decision: nil
                 },
                 %{
                   name: "confirm",
                   order: 1,
                   participant: "recipient",
                   state: "pending.sent",
                   complete?: false,
                   decision: nil
                 }
               ]
             }
    end
  end

  defmodule OptionalWorkflow do
    use ExState.Definition

    workflow "optional_steps" do
      subject :message, Message

      initial_state :working

      state :working do
        step :a
        step :b

        on_completed :b, :complete
        on_no_steps :complete
      end

      state :complete
    end

    def use_step?(%Message{review?: review}, _), do: review
  end

  test "handles no used steps" do
    message = %Message{review?: true}
    assert %{state: %{name: "working"}} = OptionalWorkflow.new(message)

    message = %Message{review?: false}
    assert %{state: %{name: "complete"}} = OptionalWorkflow.new(message)
  end

  defmodule VirtualWorkflow do
    use ExState.Definition

    workflow "virtual_states" do
      initial_state :completing_a

      virtual :working_states do
        initial_state :working

        state :working do
          step :read
          step :sign
          step :confirm
        end
      end

      state :completing_a do
        using :working_states
        on_completed :confirm, :completing_b
      end

      state :completing_b do
        using :working_states
        on_completed :confirm, :done
      end

      state :done
    end
  end

  test "uses virtual states" do
    assert {:ok, %{state: %{name: "completing_a.working"}} = execution} =
      VirtualWorkflow.new()
      |> VirtualWorkflow.complete(:read)

    assert {:ok, %{state: %{name: "completing_a.working"}} = execution} =
      execution
      |> VirtualWorkflow.complete(:sign)

    assert {:ok, %{state: %{name: "completing_b.working"}} = execution} =
      execution
      |> VirtualWorkflow.complete(:confirm)

    assert {:ok, %{state: %{name: "completing_b.working"}} = execution} =
      execution
      |> VirtualWorkflow.complete(:read)

    assert {:ok, %{state: %{name: "completing_b.working"}} = execution} =
      execution
      |> VirtualWorkflow.complete(:sign)

    assert {:ok, %{state: %{name: "done"}} = execution} =
      execution
      |> VirtualWorkflow.complete(:confirm)
  end

  defmodule FinalStateWorkflow do
    use ExState.Definition

    workflow "final_states" do
      subject :message, Message

      initial_state :composing

      state :composing do
        initial_state :thinking

        state :thinking do
          on :idea, :writing
        end

        state :writing do
          on :words, :done
        end

        state :done do
          final
        end

        on_final :sending
      end

      state :sending do
        on :send, :sent
      end

      state :sent do
        final
      end
    end
  end

  test "handles final states" do
    assert %{state: %{name: "sending"}} = execution =
      FinalStateWorkflow.new()
      |> FinalStateWorkflow.transition!(:idea)
      |> FinalStateWorkflow.transition!(:words)

    refute FinalStateWorkflow.complete?(execution)

    assert %{state: %{name: "sent"}} = execution =
      execution
      |> FinalStateWorkflow.transition!(:send)

    assert FinalStateWorkflow.complete?(execution)
  end
end
