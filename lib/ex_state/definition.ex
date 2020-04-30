defmodule ExState.Definition do
  @moduledoc """
  `ExState.Definition` provides macros to define a workflow state chart.

  A workflow is defined with a name:

      workflow "make_deal" do
        #...
      end

  ## Subject

  The subject of the workflow is used to associate the workflow for lookup
  in the database. The subject is added to the context under the defined key and
  can be used in callbacks `use_step?/2`, and `guard_transition/3`. Subject
  names and types are defined using the `subject` keyword:

      subject :deal, Deal

  ## Initial State

  A workflow must have an initial state:

      initial_state :pending

  This state must be defined using a seperate state definition.

  ## States

  States have a name, and optional sub-states, steps, and transitions:

      state :pending do
        initial_state :preparing

        state :preparing do
          on :review, :reviewing
        end

        state :reviewing do
          on :cancel, :cancelled
        end
      end

      state :cancelled

  Transitions may be a list of targets, in which case the first target state
  which is allowed by `guard_transition/3` will be used.

      state :pending do
        initial_state :preparing

        state :preparing do
          on :prepared, [:reviewing, :sending]
        end

        state :reviewing do
          on :cancel, :cancelled
        end

        state :sending do
          on :send, :sent
        end
      end

      def guard_transition(shipment, :preparing, :reviewing) do
        if shipment.requires_review? do
          :ok
        else
          {:error, "no review required"}
        end
      end

      def guard_transition(shipment, :preparing, :sending) do
        if shipment.requires_review? do
          {:error, "review required"}
        else
          :ok
        end
      end

      def guard_transition(_, _, ), do: :ok

  Transitions may also use the null event, which occurs immediately on entering
  a state. This is useful determining the initial state dynamically.

      state :unknown do
        on :_, [:a, :b]
      end

      state :a
      state :b

      def guard_transition(order, :unknown, :a), do
        if order.use_a?, do: :ok, else: {:error, :use_b}
      end

  ## Steps

  Steps must be completed in order of definition:

      state :preparing do
        step :read
        step :sign
        step :confirm
      end

  Steps can be defined in parallel, meaning any step from the block can be
  completed independent of order:

      state :preparing do
        parallel do
          step :read
          step :sign
          step :confirm
        end
      end

  Step completed events can be handled to transition to new states:

      state :preparing do
        step :read
        step :sign
        step :confirm
        on_completed :confirm, :done
      end

      state :done

  States can be ignored on a subject basis through `use_step/2`:

      def use_step(:sign, %{deal: deal}) do
        deal.requires_signature?
      end

      def use_step(_, _), do: true

  ## Virtual States

  States definitions can be reused through virtual states:

      virtual :completion_states do
        state :working do
          step :read
          step :sign
          step :confirm
        end
      end

      state :completing_a do
        using :completion_states
        on_completed :confirm, :completing_b
      end

      state :completing_b do
        using :completion_states
        on_completed :confirm, :done
      end

      state :done

  ## Decisions

  Decisions are steps that have defined options. The selection of an
  option can be used to determine state transitions:

      state :preparing do
        step :read
        step :review_terms
        on_decision :review_terms, :accept, :signing
        on_decision :review_terms, :reject, :rejected
      end

      state :signing do
        step :sign
        on_completed :sign, :done
      end

      state :rejected
      state :done

  ## Transitions

  By default, transitions reference sibling states:

      state :one do
        on :done, :two
      end

      state :two

  Transitions can reference states one level up the heirarchy (a sibling of the
  parent state) by using `{:<, :state}`, in the following form:

      state :one do
        state :a do
          on :done, {:<, :two}
        end
      end

      state :two

  Transitions can also explicitly denote legal events in the current state
  using `:_`. The following adds a transition to the current state:

      state :one do
        on :done, :two
      end

      state :two do
        on :done, :_
      end

  Transitions to the current state will reset completed steps in the current
  state by default. Step state can be preserved by using the `reset: false`
  option.

      state :one do
        step :a
        on :done, :two
        on :retry, :_, reset: true
      end

      state :two do
        step :b
        on :done, :_, reset: false
      end

  ## Guards

  Guards validate that certain dynamic conditions are met in order to
  allow state transitions:

      def guard_transition(:one, :two, %{note: note}) do
        if length(note.text) > 5 do
          :ok
        else
          {:error, "Text must be greater than 5 characters long"}
        end
      end

      def guard_transition(_, _, _), do: :ok

  Execution will stop the state transition if `{:error, reason}` is returned
  from the guard, and will allow the transition if `:ok` is returned.

  ## Actions

  Actions are side effects that happen on events. Events can be
  transitions, entering a state, or exiting a state.

      state :one do
        on_entry :send_notification
        on_entry :log_activity
        on :done, :two, action: [:update_done_at]
      end

      state :two do
        step :send_something
      end

      def update_done_at(%{note: note} = context) do
        {:updated, Map.put(context, :note, %{note | done_at: now()})}
      end

  Actions can return a `{:updated, context}` tuple to add the updated
  context to the execution state. A default `Execution.execute_actions/1`
  function is provided which executes triggered actions in a fire-and-forget
  fashion. See `ExState.persist/1` for an example of transactionally
  executing actions.

  Actions should also not explicity guard state transitions. Guards should use
  `guard_transition/3`.
  """

  alias ExState.Execution
  alias ExState.Definition.Chart

  @type state() :: atom()
  @type step() :: atom()
  @type context() :: map()
  @callback use_step?(step(), context()) :: boolean()
  @callback guard_transition(state(), state(), context()) :: :ok | {:error, any()}
  @optional_callbacks use_step?: 2, guard_transition: 3

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      require ExState.Definition.Compiler

      import unquote(__MODULE__), only: [workflow: 2]
    end
  end

  defmacro workflow(name, body) do
    chart = ExState.Definition.Compiler.compile(name, body, __CALLER__)

    quote do
      Module.put_attribute(__MODULE__, :chart, unquote(chart))

      def definition, do: @chart
      def name, do: @chart.name
      def subject, do: @chart.subject
      def initial_state, do: @chart.initial_state
      def describe, do: Chart.describe(@chart)
      def states, do: Chart.states(@chart)
      def steps, do: Chart.steps(@chart)
      def events, do: Chart.events(@chart)
      def state(id), do: Chart.state(@chart, id)
      def state(id1, id2), do: Chart.state(@chart, id1, id2)

      def new(), do: new(nil)
      def new(context), do: Execution.new(@chart, __MODULE__, context)
      def continue(state_name), do: continue(state_name, %{})

      def continue(state_name, context),
        do: Execution.continue(@chart, __MODULE__, state_name, context)

      def put_context(execution, context),
        do: Execution.put_context(execution, context)

      def put_context(execution, key, value),
        do: Execution.put_context(execution, key, value)

      def with_completed(execution, state, step, decision \\ nil),
        do: Execution.with_completed(execution, state, step, decision)

      def will_transition?(execution, event), do: Execution.will_transition?(execution, event)
      def complete?(execution), do: Execution.complete?(execution)
      def transition(execution, event), do: Execution.transition(execution, event)
      def transition!(execution, event), do: Execution.transition!(execution, event)
      def transition_maybe(execution, event), do: Execution.transition_maybe(execution, event)
      def complete(execution, step), do: Execution.complete(execution, step)
      def decision(execution, step, decision), do: Execution.decision(execution, step, decision)
      def execute_actions(execution), do: Execution.execute_actions(execution)
      def execute_actions!(execution), do: Execution.execute_actions!(execution)
      def dump(execution), do: Execution.dump(execution)
      def updated({:ok, context}), do: {:updated, context}
      def updated(x), do: x
      def updated({:ok, value}, key), do: {:updated, {key, value}}
      def updated(x, _), do: x
    end
  end
end
