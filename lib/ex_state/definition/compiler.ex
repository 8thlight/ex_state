defmodule ExState.Definition.Compiler do
  alias ExState.Definition.{
    Chart,
    State,
    Step,
    Event
  }

  def compile_workflow(name, body, env) do
    chart = compile_chart(name, body)
    chart = expand_subject_alias(chart, env)
    Macro.escape(chart)
  end

  defp compile_chart(name, body) when is_bitstring(name) do
    compile_chart(%Chart{name: name}, body)
  end

  defp compile_chart(chart, do: body) do
    compile_chart(chart, body)
  end

  defp compile_chart(chart, {:__block__, _, body}) do
    compile_chart(chart, body)
  end

  defp compile_chart(chart, body) when is_list(body) do
    Enum.reduce(body, chart, fn next, acc ->
      compile_chart(acc, next)
    end)
  end

  defp compile_chart(chart, {:subject, _, [name, queryable]}) do
    %Chart{chart | subject: {name, queryable}}
  end

  defp compile_chart(chart, {:subject, _, [name]}) do
    %Chart{chart | subject: name}
  end

  defp compile_chart(chart, {:participant, _, [name]}) do
    Chart.put_participant(chart, name)
  end

  defp compile_chart(chart, {:initial_state, _, [id]}) do
    %Chart{chart | initial_state: State.name(id)}
  end

  defp compile_chart(chart, {:state, _, [id]}) do
    compile_chart(chart, {:state, [], [id, []]})
  end

  defp compile_chart(%Chart{states: states} = chart, {:state, _, [id, body]}) do
    more_states = compile_state(id, body)

    merged_states =
      Enum.reduce(more_states, states, fn next, acc ->
        Map.put(acc, next.name, next)
      end)

    %Chart{chart | states: merged_states}
  end

  defp compile_state(id, body) when is_atom(id) do
    compile_state(nil, id, body)
  end

  defp compile_state(current, id, body) when is_atom(id) do
    compile_state(current, State.name(id), body)
  end

  defp compile_state(current, name, body) when is_bitstring(name) do
    full_name = State.child(current, name)
    compile_state(full_name, [%State{name: full_name}], body)
  end

  defp compile_state(current, states, do: body) do
    compile_state(current, states, body)
  end

  defp compile_state(current, states, {:__block__, _, body}) do
    compile_state(current, states, body)
  end

  defp compile_state(current, states, body) when is_list(body) do
    Enum.reduce(body, states, fn next, acc ->
      compile_state(current, acc, next)
    end)
  end

  defp compile_state(current, states, {:state, _, [id, body]}) do
    next_states = compile_state(current, id, body)
    next_states ++ states
  end

  defp compile_state(current, [%State{} = state | rest], {:initial_state, _, [id]}) do
    [%State{state | initial_state: State.child(current, id)} | rest]
  end

  defp compile_state(_current, [state | rest], {:parallel, _, [[do: {:__block__, _, body}]]}) do
    steps =
      Enum.map(body, fn
        {:step, _, [id]} -> Step.new(id, nil)
        {:step, _, [id, opts]} -> Step.new(id, Keyword.get(opts, :participant))
      end)

    [State.add_parallel_steps(state, steps) | rest]
  end

  defp compile_state(current, states, {:step, _, [id]}) do
    compile_state(current, states, {:step, [], [id, []]})
  end

  defp compile_state(_current, [state | rest], {:step, _, [id, opts]}) do
    repeatable = Keyword.get(opts, :repeatable)
    step = Step.new(id, Keyword.get(opts, :participant))
    state = State.add_step(state, step)

    state =
      if repeatable do
        State.add_repeatable_step(state, Step.name(id))
      else
        state
      end

    [state | rest]
  end

  defp compile_state(_current, [state | rest], {:repeatable, _, [step_id]}) do
    [State.add_repeatable_step(state, Step.name(step_id)) | rest]
  end

  defp compile_state(_current, [state | rest], {:on_entry, _, [action]}) do
    [State.add_action(state, :entry, action) | rest]
  end

  defp compile_state(_current, [state | rest], {:on_exit, _, [action]}) do
    [State.add_action(state, :exit, action) | rest]
  end

  defp compile_state(current, states, {:on_completed, _, [step, next_state]}) do
    compile_state(current, states, {:on, [], [{:completed, step}, next_state]})
  end

  defp compile_state(current, states, {:on_completed, _, [step, next_state, options]}) do
    compile_state(current, states, {:on, [], [{:completed, step}, next_state, options]})
  end

  defp compile_state(current, states, {:on_decision, _, [step, decision, next_state]}) do
    compile_state(current, states, {:on, [], [{:decision, step, decision}, next_state]})
  end

  defp compile_state(current, states, {:on_decision, _, [step, decision, next_state, options]}) do
    compile_state(current, states, {:on, [], [{:decision, step, decision}, next_state, options]})
  end

  defp compile_state(current, states, {:on_no_steps, _, [next_state]}) do
    compile_state(current, states, {:on, [], [:no_steps, next_state]})
  end

  defp compile_state(current, states, {:on_no_steps, _, [next_state, options]}) do
    compile_state(current, states, {:on, [], [:no_steps, next_state, options]})
  end

  defp compile_state(current, states, {:on, _, [id, next_state]}) do
    compile_state(current, states, {:on, [], [id, next_state, []]})
  end

  defp compile_state(current, [state | rest], {:on, _, [id, next_state, opts]}) do
    event = Event.new(id, State.resolve(current, next_state), opts)
    [State.add_transition(state, event) | rest]
  end

  defp compile_state(_current, states, _) when is_list(states) do
    states
  end

  defp expand_subject_alias(%Chart{subject: {name, queryable}} = chart, env) do
    %Chart{chart | subject: {name, Macro.expand(queryable, env)}}
  end

  defp expand_subject_alias(chart, _env) do
    chart
  end
end
