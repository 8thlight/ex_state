defmodule ExState.Definition.Execution do
  alias ExState.Definition.Chart
  alias ExState.Definition.State
  alias ExState.Definition.Step
  alias ExState.Definition.Event

  @type t :: %__MODULE__{
          chart: Chart.t(),
          state: State.t(),
          actions: [atom()],
          history: [State.t()],
          transitions: [Event.t()],
          callback_mod: module(),
          subject: any()
        }

  defstruct chart: %Chart{},
            state: nil,
            actions: [],
            history: [],
            transitions: [],
            callback_mod: nil,
            subject: nil

  def new(workflow, subject) do
    new(workflow.definition, workflow, subject)
  end

  def new(chart, callback_mod, subject) do
    %__MODULE__{chart: chart, callback_mod: callback_mod, subject: subject}
    |> enter_state(chart.initial_state)
  end

  def continue(workflow, subject, state_name) do
    continue(workflow.definition, workflow, subject, state_name)
  end

  def continue(chart, callback_mod, subject, state_name) when is_bitstring(state_name) do
    %__MODULE__{chart: chart, callback_mod: callback_mod, subject: subject}
    |> enter_state(state_name, entry_actions: false)
  end

  def with_completed(execution, state_name, step_name, decision \\ nil)

  def with_completed(
        %__MODULE__{state: %State{name: state_name}} = execution,
        state_name,
        step_name,
        decision
      ) do
    put_state(execution, State.put_completed_step(execution.state, step_name, decision))
  end

  def with_completed(execution, state_name, step_name, decision) do
    case Enum.find(execution.history, fn state -> state.name == state_name end) do
      nil ->
        put_history(
          execution,
          State.put_completed_step(get_state(execution, state_name), step_name, decision)
        )

      state ->
        put_history(
          execution,
          Enum.map(execution.history, fn
            %State{name: ^state_name} -> State.put_completed_step(state, step_name, decision)
            state -> state
          end)
        )
    end
  end

  defp enter_state(execution, name, opts \\ [])

  defp enter_state(execution, name, opts) when is_bitstring(name) do
    enter_state(execution, get_state(execution, name), opts)
  end

  defp enter_state(execution, %State{} = state, opts) do
    execution
    |> put_history()
    |> put_state(state)
    |> filter_steps()
    |> put_actions(opts)
    |> enter_initial_state()
    |> handle_no_steps()
  end

  defp enter_initial_state(%__MODULE__{state: %State{initial_state: nil}} = execution) do
    execution
  end

  defp enter_initial_state(%__MODULE__{state: %State{initial_state: initial_state}} = execution) do
    enter_state(execution, get_state(execution, initial_state))
  end

  defp handle_no_steps(%__MODULE__{state: %State{steps: []}} = execution) do
    transition(execution, :no_steps)
  end

  defp handle_no_steps(execution) do
    execution
  end

  defp filter_steps(%__MODULE__{state: state} = execution) do
    put_state(execution, State.filter_steps(state, fn step -> use_step?(execution, step) end))
  end

  defp put_history(%__MODULE__{state: nil} = execution), do: execution

  defp put_history(execution) do
    put_history(execution, execution.state)
  end

  defp put_history(execution, %State{} = state) do
    put_history(execution, [state | execution.history])
  end

  defp put_history(execution, history) when is_list(history) do
    %__MODULE__{execution | history: history}
  end

  def get_state(execution, name) do
    Chart.state(execution.chart, name)
  end

  def put_state(execution, state) do
    %__MODULE__{execution | state: state}
  end

  def put_transition(execution, transition) do
    %__MODULE__{execution | transitions: [transition | execution.transitions]}
  end

  @spec complete(t(), atom()) :: {:ok, t()} | {:error, String.t(), t()}
  def complete(execution, step_id) do
    case State.complete_step(execution.state, step_id) do
      {:ok, state} ->
        case do_transition(put_state(execution, state), {:completed, step_id}) do
          {:ok, execution} ->
            {:ok, execution}

          {:error, :no_transition, _reason, execution} ->
            {:ok, execution}

          {:error, _kind, reason, execution} ->
            {:error, reason, execution}
        end

      {:error, next_steps, state} ->
        {:error, step_error(next_steps), put_state(execution, state)}
    end
  end

  @spec decision(t(), atom(), atom()) :: {:ok, t()} | {:error, String.t(), t()}
  def decision(execution, step_id, decision) do
    case State.complete_step(execution.state, step_id, decision) do
      {:ok, state} ->
        case do_transition(put_state(execution, state), {:decision, step_id, decision}) do
          {:ok, execution} ->
            {:ok, execution}

          {:error, _kind, reason, execution} ->
            {:error, reason, execution}
        end

      {:error, next_steps, state} ->
        {:error, step_error(next_steps), put_state(execution, state)}
    end
  end

  defp step_error([]), do: "no next step"
  defp step_error([next_step]), do: "next step is: #{next_step.name}"

  defp step_error(next_steps) when is_list(next_steps) do
    "next steps are: #{Enum.map(next_steps, fn step -> step.name end) |> Enum.join(", ")}"
  end

  @spec transition_result(t(), Event.name()) :: {:ok, t()} | {:error, String.t(), t()}
  def transition_result(execution, event) do
    case do_transition(execution, event) do
      {:ok, execution} ->
        {:ok, execution}

      {:error, _kind, reason, execution} ->
        {:error, reason, execution}
    end
  end

  def transition(execution, event) do
    case do_transition(execution, event) do
      {:ok, execution} ->
        execution

      {:error, _kind, _reason, execution} ->
        execution
    end
  end

  @spec do_transition(t(), Event.name()) :: {:ok, t()} | {:error, atom(), any(), t()}
  defp do_transition(%__MODULE__{state: %State{name: current_state}} = execution, event) do
    case State.transition(execution.state, event) do
      nil ->
        case Chart.parent(execution.chart, execution.state) do
          nil ->
            {:error, :no_transition,
             "no transition from #{execution.state.name} for event #{inspect(event)}", execution}

          parent ->
            case do_transition(put_state(execution, parent), event) do
              {:ok, execution} ->
                {:ok, execution}

              {:error, kind, reason, _} ->
                {:error, kind, reason, execution}
            end
        end

      %Event{next_state: ^current_state, reset: false} = transition ->
        next =
          execution
          |> add_actions(transition.actions)

        {:ok, next}

      transition ->
        case get_state(execution, transition.next_state) do
          nil ->
            {:error, :no_state, "no state found for transition to #{transition.next_state}",
             execution}

          next_state ->
            case guard_transition(execution, next_state) do
              :ok ->
                next =
                  execution
                  |> put_transition(transition)
                  |> enter_state(next_state)

                {:ok, next}

              {:error, reason} ->
                {:error, :guard_transition, reason, execution}
            end
        end
    end
  end

  defp guard_transition(execution, next_state) do
    if function_exported?(execution.callback_mod, :guard_transition, 3) do
      execution.callback_mod.guard_transition(
        execution.subject,
        State.id(execution.state),
        State.id(next_state)
      )
    else
      :ok
    end
  end

  def will_transition?(execution, event) do
    transition(execution, event).state != execution.state
  end

  def complete?(execution), do: State.final?(execution.state)

  def dump(execution) do
    participants = participants(execution)

    %{
      name: execution.chart.name,
      state: execution.state.name,
      complete?: complete?(execution),
      steps: dump_steps(execution, participants),
      participants: participants,
      subject: dump_subject(execution)
    }
  end

  defp dump_subject(execution) do
    case execution.chart.subject do
      nil -> nil
      {key, _} -> {key, execution.subject}
      key -> key
    end
  end

  defp dump_steps(execution, participants) do
    execution
    |> merge_states()
    |> Enum.flat_map(fn state ->
      state.steps
      |> Enum.filter(fn step -> use_step?(execution, step) end)
      |> Enum.map(fn step ->
        %{
          state: state.name,
          order: step.order,
          name: step.name,
          complete?: step.complete?,
          decision: step.decision,
          participant: Enum.find(participants, fn p -> p.name == step.participant end)
        }
      end)
    end)
  end

  defp merge_states(execution) do
    Enum.map(execution.chart.states, fn {_, state} ->
      case execution.state.name == state.name do
        true ->
          execution.state

        false ->
          case Enum.find(execution.history, fn s -> s.name == state.name end) do
            nil -> state
            history_state -> history_state
          end
      end
    end)
  end

  defp use_step?(execution, step) do
    if function_exported?(execution.callback_mod, :use_step?, 2) do
      execution.callback_mod.use_step?(execution.subject, Step.id(step))
    else
      true
    end
  end

  defp participants(execution) do
    Enum.map(execution.chart.participants, fn name ->
      participant(execution, name)
    end)
  end

  defp participant(execution, name) do
    if function_exported?(execution.callback_mod, :participant, 2) do
      %{
        name: name,
        id: execution.callback_mod.participant(execution.subject, name)
      }
    else
      nil
    end
  end

  defp put_actions(execution, opts) do
    if Keyword.get(opts, :entry_actions, true) do
      execution
      |> put_exit_actions()
      |> put_transition_actions()
      |> put_entry_actions()
    else
      execution
      |> put_exit_actions()
      |> put_transition_actions()
    end
  end

  def execute_actions(execution) do
    execution.actions
    |> Enum.reverse()
    |> Enum.reduce({:ok, %{}}, fn
      _next, {:error, _reason} = e ->
        e

      next, {:ok, acc} ->
        case execute_action(execution, next) do
          :ok -> {:ok, acc}
          {:ok, result} -> {:ok, Map.put(acc, next, result)}
          {:error, _reason} = e -> e
        end
    end)
    |> case do
      {:ok, results} ->
        {:ok, reset_actions(execution), results}

      {:error, reason} ->
        {:error, execution, reason}
    end
  end

  def execute_action(execution, action) do
    if function_exported?(execution.callback_mod, action, 1) do
      apply(execution.callback_mod, action, [execution.subject])
    end
  end

  defp reset_actions(execution) do
    %__MODULE__{execution | actions: []}
  end

  defp add_actions(execution, actions) do
    %__MODULE__{execution | actions: actions ++ execution.actions}
  end

  defp put_exit_actions(%__MODULE__{state: current, history: [last | _rest]} = execution) do
    cond do
      State.child?(last, current) ->
        execution

      !State.sibling?(last, current) ->
        execution
        |> add_actions(State.actions(last, :exit))
        |> add_actions(State.actions(Chart.parent(execution.chart, last), :exit))

      true ->
        add_actions(execution, State.actions(last, :exit))
    end
  end

  defp put_exit_actions(execution), do: execution

  defp put_transition_actions(%__MODULE__{transitions: [last | _rest]} = execution) do
    add_actions(execution, last.actions)
  end

  defp put_transition_actions(execution), do: execution

  defp put_entry_actions(%__MODULE__{state: current} = execution) do
    add_actions(execution, State.actions(current, :entry))
  end
end
