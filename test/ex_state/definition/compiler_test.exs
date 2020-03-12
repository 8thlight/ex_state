defmodule ExState.Definition.CompilerTest do
  use ExUnit.Case, async: true

  defmodule Thing do
    defstruct [:id]
  end

  defmodule TestWorkflow do
    use ExState.Definition

    workflow "test" do
      subject :thing, Thing

      participant :seller
      participant :buyer

      initial_state :working

      state :working do
        on_entry :notify_working
        on_entry :log_stuff
        on_exit :notify_not_working

        initial_state :subscription

        on :reject, :rejected
        on :close, :closed

        state :subscription do
          initial_state :accepting

          state :accepting do
            step :accept, participant: :seller
            on_completed :accept, :confirming
          end

          state :confirming do
            repeatable :accept
            step :confirm, participant: :seller
            on_completed :confirming, :submitting
          end

          state :submitting do
            step :acknowledge, participant: :seller
            step :sign, participant: :seller
            on_completed :sign, {:<, :execution}
          end
        end

        state :execution do
          initial_state :accepting

          state :accepting do
            step :acknowledge, participant: :buyer
            step :countersign, participant: :buyer
            on_completed :countersign, :funding
          end
        end

        state :funding do
          initial_state :sending_funds

          state :sending_funds do
            step :send, participant: :seller

            parallel do
              step :verify
              step :evaluate, participant: :seller
            end

            on_decision :evaluate, :good, :closed
            on_decision :evaluate, :bad, :rejected
          end
        end
      end

      state :rejected do
        final
      end

      state :closed do
        final
      end
    end

    def log_stuff(_), do: :ok
    def notify_working(_), do: :ok
    def notify_not_working(_), do: :ok
  end

  test "compiles a workflow definition" do
    assert TestWorkflow.definition() ==
             %ExState.Definition.Chart{
               initial_state: "working",
               name: "test",
               subject: {:thing, ExState.Definition.CompilerTest.Thing},
               participants: [:buyer, :seller],
               states: %{
                 "closed" => %ExState.Definition.State{
                   type: :final,
                   initial_state: nil,
                   name: "closed",
                   steps: [],
                   transitions: %{}
                 },
                 "rejected" => %ExState.Definition.State{
                   type: :final,
                   initial_state: nil,
                   name: "rejected",
                   steps: [],
                   transitions: %{}
                 },
                 "working" => %ExState.Definition.State{
                   type: :compound,
                   actions: %{
                     entry: [:log_stuff, :notify_working],
                     exit: [:notify_not_working]
                   },
                   initial_state: "working.subscription",
                   name: "working",
                   steps: [],
                   transitions: %{
                     close: %ExState.Definition.Event{
                       name: :close,
                       next_state: "closed"
                     },
                     reject: %ExState.Definition.Event{
                       name: :reject,
                       next_state: "rejected"
                     }
                   }
                 },
                 "working.execution" => %ExState.Definition.State{
                   type: :compound,
                   initial_state: "working.execution.accepting",
                   name: "working.execution",
                   steps: [],
                   transitions: %{}
                 },
                 "working.execution.accepting" => %ExState.Definition.State{
                   type: :atomic,
                   initial_state: nil,
                   name: "working.execution.accepting",
                   steps: [
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "countersign",
                       order: 2,
                       participant: :buyer
                     },
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "acknowledge",
                       order: 1,
                       participant: :buyer
                     }
                   ],
                   transitions: %{
                     {:completed, :countersign} => %ExState.Definition.Event{
                       name: {:completed, :countersign},
                       next_state: "working.execution.funding"
                     }
                   }
                 },
                 "working.funding" => %ExState.Definition.State{
                   type: :compound,
                   initial_state: "working.funding.sending_funds",
                   name: "working.funding",
                   steps: [],
                   transitions: %{}
                 },
                 "working.funding.sending_funds" => %ExState.Definition.State{
                   type: :atomic,
                   initial_state: nil,
                   name: "working.funding.sending_funds",
                   steps: [
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "evaluate",
                       order: 2,
                       participant: :seller
                     },
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "verify",
                       order: 2,
                       participant: nil
                     },
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "send",
                       order: 1,
                       participant: :seller
                     }
                   ],
                   transitions: %{
                     {:decision, :evaluate, :bad} => %ExState.Definition.Event{
                       name: {:decision, :evaluate, :bad},
                       next_state: "working.funding.rejected"
                     },
                     {:decision, :evaluate, :good} => %ExState.Definition.Event{
                       name: {:decision, :evaluate, :good},
                       next_state: "working.funding.closed"
                     }
                   }
                 },
                 "working.subscription" => %ExState.Definition.State{
                   type: :compound,
                   initial_state: "working.subscription.accepting",
                   name: "working.subscription",
                   steps: [],
                   transitions: %{}
                 },
                 "working.subscription.accepting" => %ExState.Definition.State{
                   type: :atomic,
                   initial_state: nil,
                   name: "working.subscription.accepting",
                   steps: [
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "accept",
                       order: 1,
                       participant: :seller
                     }
                   ],
                   transitions: %{
                     {:completed, :accept} => %ExState.Definition.Event{
                       name: {:completed, :accept},
                       next_state: "working.subscription.confirming"
                     }
                   }
                 },
                 "working.subscription.confirming" => %ExState.Definition.State{
                   type: :atomic,
                   initial_state: nil,
                   name: "working.subscription.confirming",
                   steps: [
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "confirm",
                       order: 1,
                       participant: :seller
                     }
                   ],
                   repeatable_steps: ["accept"],
                   transitions: %{
                     {:completed, :confirming} => %ExState.Definition.Event{
                       name: {:completed, :confirming},
                       next_state: "working.subscription.submitting"
                     }
                   }
                 },
                 "working.subscription.submitting" => %ExState.Definition.State{
                   type: :atomic,
                   initial_state: nil,
                   name: "working.subscription.submitting",
                   steps: [
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "sign",
                       order: 2,
                       participant: :seller
                     },
                     %ExState.Definition.Step{
                       complete?: false,
                       decision: nil,
                       name: "acknowledge",
                       order: 1,
                       participant: :seller
                     }
                   ],
                   transitions: %{
                     {:completed, :sign} => %ExState.Definition.Event{
                       name: {:completed, :sign},
                       next_state: "working.execution"
                     }
                   }
                 }
               }
             }
  end
end
