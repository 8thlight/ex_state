defmodule ExState.Definition.State do
  alias ExState.Definition.Step
  alias ExState.Definition.Transition

  @type state_type :: :atomic | :compound | :final

  @type t :: %__MODULE__{
          name: String.t(),
          type: state_type(),
          initial_state: String.t(),
          steps: [Step.t()],
          ignored_steps: [Step.t()],
          repeatable_steps: [String.t()],
          transitions: %{required(Transition.event()) => Transition.t()},
          actions: %{required(Transition.event()) => atom()}
        }

  defstruct name: nil,
            type: :atomic,
            initial_state: nil,
            steps: [],
            ignored_steps: [],
            repeatable_steps: [],
            transitions: %{},
            actions: %{}

  def transition(state, event) do
    Map.get(state.transitions, event)
  end

  def transitions(state) do
    state.transitions
    |> Map.values()
    |> Enum.reduce([], fn transition, events ->
      case transition.event do
        {:completed, _step} -> events
        {:decision, _step, _decision} -> events
        event_name when is_atom(event_name) -> [%{event: event_name, state: state.name} | events]
      end
    end)
  end

  def actions(state, event) do
    Map.get(state.actions, event, [])
  end

  def add_transition(state, transition) do
    %__MODULE__{state | transitions: Map.put(state.transitions, transition.event, transition)}
  end

  def add_action(state, event, action) do
    %__MODULE__{
      state
      | actions: Map.update(state.actions, event, [action], fn actions -> [action | actions] end)
    }
  end

  def add_step(state, step) do
    add_step(state, step, Enum.count(state.steps) + 1)
  end

  def add_step(state, step, order) do
    %__MODULE__{state | steps: [Step.order(step, order) | state.steps]}
  end

  def add_parallel_steps(state, steps) do
    order = Enum.count(state.steps) + 1

    Enum.reduce(steps, state, fn step, state ->
      add_step(state, step, order)
    end)
  end

  def add_repeatable_step(state, step) do
    %__MODULE__{state | repeatable_steps: [step | state.repeatable_steps]}
  end

  def repeatable?(state, step_name) do
    if Enum.member?(state.repeatable_steps, step_name) do
      case Enum.find(state.steps ++ state.ignored_steps, fn step -> step.name == step_name end) do
        nil ->
          true

        step ->
          step.complete?
      end
    else
      false
    end
  end

  def filter_steps(state, filter) do
    {ignored, steps} =
      Enum.reduce(state.steps, {[], []}, fn step, {ignored, steps} ->
        if filter.(step) do
          {ignored, [step | steps]}
        else
          {[step | ignored], steps}
        end
      end)

    %__MODULE__{state | steps: Enum.reverse(steps), ignored_steps: Enum.reverse(ignored)}
  end

  def next_steps(state) do
    state.steps
    |> Enum.filter(fn step -> !step.complete? end)
    |> Enum.sort_by(fn step -> step.order end)
    |> Enum.chunk_by(fn step -> step.order end)
    |> List.first()
  end

  def complete_step(state, name, decision \\ nil)

  def complete_step(state, id, decision) when is_atom(id) do
    complete_step(state, Step.name(id), decision)
  end

  def complete_step(state, name, decision) when is_bitstring(name) do
    case next_steps(state) do
      nil ->
        if repeatable?(state, name) do
          {:ok, state}
        else
          {:error, [], state}
        end

      next_steps ->
        case Enum.any?(next_steps, fn step -> step.name == name end) do
          true ->
            {:ok, put_completed_step(state, name, decision)}

          false ->
            if repeatable?(state, name) do
              {:ok, state}
            else
              {:error, next_steps, state}
            end
        end
    end
  end

  def put_completed_step(state, name, decision \\ nil) when is_bitstring(name) do
    steps =
      Enum.map(state.steps, fn
        %Step{name: ^name} = step -> Step.complete(step, decision)
        step -> step
      end)

    %__MODULE__{state | steps: steps}
  end

  def final?(%__MODULE__{type: :final}), do: true
  def final?(%__MODULE__{}), do: false

  def child?(%__MODULE__{} = state, %__MODULE__{} = child_maybe) do
    combine(drop_last(child_maybe.name)) == state.name
  end

  def sibling?(%__MODULE__{} = state, %__MODULE__{} = sibling_maybe) do
    combine(drop_last(state.name)) == combine(drop_last(sibling_maybe.name))
  end

  def name(id) when is_atom(id), do: Atom.to_string(id)
  def name(id) when is_bitstring(id), do: id

  # The atom may not exist due to being converted to string at compile time.
  # Should be safe to use to_atom here since this API shouldn't be
  # exposed to external input.
  def id(state), do: state.name |> last() |> String.to_atom()

  def resolve(nil, next) when is_atom(next), do: next
  def resolve(current, next) when is_list(next), do: Enum.map(next, &resolve(current, &1))
  def resolve(current, :_), do: current

  def resolve(current, {:<, next}) when is_atom(next) do
    current
    |> parent()
    |> sibling(next)
  end

  def resolve(current, next) when is_atom(next) do
    current
    |> sibling(next)
  end

  def parent(nil), do: nil

  def parent(state) do
    state
    |> split()
    |> drop_last()
    |> combine()
  end

  def child(nil, state), do: state

  def child(current, state) do
    current
    |> split()
    |> append(state)
    |> combine()
  end

  def sibling(nil, state), do: state

  def sibling(current, state) do
    current
    |> split()
    |> drop_last()
    |> append(state)
    |> combine()
  end

  def drop_last(name) when is_bitstring(name), do: split(name) |> drop_last()
  def drop_last(states) when is_list(states), do: Enum.drop(states, -1)
  def append(states, state), do: List.insert_at(states, -1, state)
  def split(state), do: String.split(state, ".")
  def last(state), do: split(state) |> List.last()
  def combine(states), do: Enum.join(states, ".")
end
