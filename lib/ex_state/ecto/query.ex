defmodule ExState.Ecto.Query do
  @moduledoc """
  `ExState.Ecto.Query` provides functions for querying workflow state in the
  database through Ecto.
  """

  import Ecto.Query

  @doc """
  where_state/2 takes a subject query and state and filters based on workflows that are in the
  exact state that is passed. Nested states can be passed as a list of states and will be converted
  to a valid state identifier in the query.

  Pass the state as the keyword list `not: state` in order to query the inverse.

  Examples:

    investment #=> %Investment{workflow: %Workflow{state: "subscribing.confirming_options"}}

    Investment
    |> where_state("subscribing.confirming_options")
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_state([:subscribing, :confirming_options])
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_state(["subscribing", "confirming_options"])
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_state(:subscribing)
    |> Repo.all()                                                 #=> []

    Investment
    |> where_state(not: [:subscribing, :confirming_suitability])
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_state(not: [:subscribing, :confirming_options])
    |> Repo.all()                                                 #=> []
  """
  def where_state(subject_query, not: state) do
    subject_query
    |> join_workflow_maybe()
    |> where([workflow: workflow], workflow.state != ^to_state_id(state))
  end

  def where_state(subject_query, state) do
    subject_query
    |> join_workflow_maybe()
    |> where([workflow: workflow], workflow.state == ^to_state_id(state))
  end

  @doc """
  where_state_in/2 takes a subject query and a list of states and filters based on workflows that
  are in one of the exact states that are passed. Nested states can be passed as a list of states
  and will be converted to a valid state identifier in the query.

  Pass the state as the keyword list `not: state` in order to query the inverse.

  Examples:

    investment1 #=> %Investment{workflow: %Workflow{state: "subscribing.confirming_options"}}
    investment2 #=> %Investment{workflow: %Workflow{state: "executed"}}

    Investment
    |> where_state_in([
      [:subscribing, :confirming_options],
      :executed
    ])
    |> Repo.all()                                                 #=> [investment1, investment2]

    Investment
    |> where_state_in(["subscribing.confirming_options"])
    |> Repo.all()                                                 #=> [investment1]

    Investment
    |> where_state_in([:subscribing])
    |> Repo.all()                                                 #=> []

    Investment
    |> where_state_in(not: [[:subscribing, :confirming_options]])
    |> Repo.all()                                                 #=> [investment2]

    Investment
    |> where_state_in(not: [:subscribing])
    |> Repo.all()                                                 #=> [investment1, investment2]
  """
  def where_state_in(subject_query, not: states) do
    subject_query
    |> join_workflow_maybe()
    |> where([workflow: workflow], workflow.state not in ^Enum.map(states, &to_state_id/1))
  end

  def where_state_in(subject_query, states) do
    subject_query
    |> join_workflow_maybe()
    |> where([workflow: workflow], workflow.state in ^Enum.map(states, &to_state_id/1))
  end

  @doc """
  where_any_state/2 takes a subject query and a state and filters based on workflows that are equal
  to or in a child state of the given state. Nested states can be passed as a list of states
  and will be converted to a valid state identifier in the query.

  Examples:

    investment #=> %Investment{workflow: %Workflow{state: "subscribing.confirming_options"}}

    Investment
    |> where_any_state(:subscribing)
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_any_state("subscribing")
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_any_state([:subscribing, :confirming_options])
    |> Repo.all()                                                 #=> [investment]

    Investment
    |> where_any_state(:resubmitting)
    |> Repo.all()                                                 #=> []
  """
  def where_any_state(subject_query, state) do
    state_id = to_state_id(state)

    subject_query
    |> join_workflow_maybe()
    |> where(
      [workflow: workflow],
      workflow.state == ^state_id or ilike(workflow.state, ^"#{state_id}.%")
    )
  end

  def where_step_complete(q, s) when is_atom(s),
    do: where_step_complete(q, Atom.to_string(s))

  def where_step_complete(subject_query, step_name) do
    subject_query
    |> join_workflow_maybe()
    |> join_workflow_steps_maybe()
    |> where([workflow_step: step], step.name == ^step_name and step.complete?)
  end

  def to_state_id(states) when is_list(states) do
    Enum.map(states, &to_state_id/1) |> Enum.join(".")
  end

  def to_state_id(state) when is_atom(state), do: Atom.to_string(state)
  def to_state_id(state) when is_bitstring(state), do: state

  def to_state_list(state) when is_bitstring(state) do
    String.split(state, ".") |> Enum.map(&String.to_atom/1)
  end

  def to_step_name(step) when is_atom(step), do: Atom.to_string(step)
  def to_step_name(step) when is_bitstring(step), do: step

  defp join_workflow_maybe(subject_query) do
    if has_named_binding?(subject_query, :workflow) do
      subject_query
    else
      join(subject_query, :inner, [sub], w in assoc(sub, :workflow), as: :workflow)
    end
  end

  defp join_workflow_steps_maybe(subject_query) do
    if has_named_binding?(subject_query, :workflow_step) do
      subject_query
    else
      join(subject_query, :inner, [workflow: w], s in assoc(w, :steps), as: :workflow_step)
    end
  end
end
