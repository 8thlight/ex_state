defmodule ExState.Definition.Chart do
  alias ExState.Definition.State

  @type subject :: {atom(), module()}

  @type t :: %__MODULE__{
          name: String.t(),
          subject: subject() | nil,
          initial_state: atom(),
          states: %{required(String.t()) => State.t()},
          participants: [atom()]
        }

  defstruct name: nil, subject: nil, initial_state: nil, states: %{}, participants: []

  def transitions(chart) do
    chart.states
    |> Map.values()
    |> Enum.flat_map(&State.transitions/1)
  end

  def events(chart) do
    chart
    |> transitions()
    |> Enum.map(fn transition -> Atom.to_string(transition.event) end)
    |> Enum.uniq()
  end

  def states(chart) do
    Map.values(chart.states)
  end

  def state_names(chart) do
    chart
    |> states()
    |> Enum.map(fn state -> state.name end)
  end

  def steps(chart) do
    chart.states
    |> Enum.flat_map(fn {_, state} -> state.steps end)
  end

  def step_names(chart) do
    chart
    |> steps()
    |> Enum.map(fn step -> step.name end)
  end

  def state(chart, name) when is_bitstring(name) do
    Map.get(chart.states, name)
  end

  def state(chart, id) when is_atom(id) do
    state(chart, State.combine([id]))
  end

  def state(chart, id1, id2) when is_atom(id1) and is_atom(id2) do
    state(chart, State.combine([id1, id2]))
  end

  def parent(chart, %State{name: name}) do
    state(chart, State.parent(name))
  end

  def put_states(chart, states) do
    %__MODULE__{chart | states: states}
  end

  def put_participant(chart, participant) do
    %__MODULE__{chart | participants: [participant | chart.participants]}
  end

  def participant_names(chart) do
    chart.participants
    |> Enum.map(&Atom.to_string/1)
  end

  def describe(chart) do
    %{
      "states" => state_names(chart),
      "steps" => step_names(chart),
      "events" => events(chart),
      "participants" => participant_names(chart)
    }
  end
end
