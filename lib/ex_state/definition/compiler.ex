defmodule ExState.Definition.Compiler do
  alias ExState.Definition.{
    Chart,
    State,
    Step,
    Transition
  }

  defmodule Env do
    defstruct chart: nil,
              macro_env: nil,
              virtual_states: %{}
  end

  def compile(name, body, macro_env) do
    env = do_compile(name, body, macro_env)
    chart = expand_subject_alias(env.chart, macro_env)
    Macro.escape(chart)
  end

  defp do_compile(name, body, env) do
    chart = %Chart{name: name}
    env = %Env{chart: chart, macro_env: env}
    compile_chart(env, body)
  end

  defp compile_chart(%Env{} = env, do: body) do
    compile_chart(env, body)
  end

  defp compile_chart(%Env{} = env, {:__block__, _, body}) do
    compile_chart(env, body)
  end

  defp compile_chart(%Env{} = env, body) when is_list(body) do
    Enum.reduce(body, env, fn next, acc ->
      compile_chart(acc, next)
    end)
  end

  defp compile_chart(%Env{chart: chart} = env, {:subject, _, [name, queryable]}) do
    %Env{env | chart: %Chart{chart | subject: {name, queryable}}}
  end

  defp compile_chart(%Env{chart: chart} = env, {:participant, _, [name]}) do
    %Env{env | chart: Chart.put_participant(chart, name)}
  end

  defp compile_chart(%Env{chart: chart} = env, {:initial_state, _, [id]}) do
    %Env{env | chart: %Chart{chart | initial_state: State.name(id)}}
  end

  defp compile_chart(%Env{virtual_states: virtual_states} = env, {:virtual, _, [name, body]}) do
    %Env{env | virtual_states: Map.put(virtual_states, name, body)}
  end

  defp compile_chart(%Env{} = env, {:state, _, [id]}) do
    compile_chart(env, {:state, [], [id, []]})
  end

  defp compile_chart(%Env{chart: %Chart{states: states} = chart} = env, {:state, _, [id, body]}) do
    more_states = compile_state(env, id, body)

    merged_states =
      Enum.reduce(more_states, states, fn next, acc ->
        Map.put(acc, next.name, next)
      end)

    %Env{env | chart: %Chart{chart | states: merged_states}}
  end

  defp compile_state(env, id, body) when is_atom(id) do
    compile_state(env, nil, id, body)
  end

  defp compile_state(env, current, id, body) when is_atom(id) do
    compile_state(env, current, State.name(id), body)
  end

  defp compile_state(env, current, name, body) when is_bitstring(name) do
    full_name = State.child(current, name)
    compile_state(env, full_name, [%State{name: full_name}], body)
  end

  defp compile_state(env, current, states, do: body) do
    compile_state(env, current, states, body)
  end

  defp compile_state(env, current, states, {:__block__, _, body}) do
    compile_state(env, current, states, body)
  end

  defp compile_state(env, current, [%State{name: name} | _rest] = states, body)
       when is_list(body) do
    Enum.reduce(body, states, fn
      {:state, _, _} = next, [%State{name: ^name} = state | rest] ->
        acc = [%State{state | type: :compound} | rest]
        compile_state(env, current, acc, next)

      next, acc ->
        compile_state(env, current, acc, next)
    end)
  end

  defp compile_state(env, current, states, {:using, _, [id]}) do
    body = Map.get(env.virtual_states, id, [])
    compile_state(env, current, states, body)
  end

  defp compile_state(env, current, states, {:state, _, [id, body]}) do
    next_states = compile_state(env, current, id, body)
    next_states ++ states
  end

  defp compile_state(_env, current, [%State{} = state | rest], {:initial_state, _, [id]}) do
    [%State{state | initial_state: State.child(current, id)} | rest]
  end

  defp compile_state(_env, _current, [state | rest], {:final, _, nil}) do
    [%State{state | type: :final} | rest]
  end

  defp compile_state(
         _env,
         _current,
         [state | rest],
         {:parallel, _, [[do: {:__block__, _, body}]]}
       ) do
    steps =
      Enum.map(body, fn
        {:step, _, [id]} -> Step.new(id, nil)
        {:step, _, [id, opts]} -> Step.new(id, Keyword.get(opts, :participant))
      end)

    [State.add_parallel_steps(state, steps) | rest]
  end

  defp compile_state(env, current, states, {:step, _, [id]}) do
    compile_state(env, current, states, {:step, [], [id, []]})
  end

  defp compile_state(_env, _current, [state | rest], {:step, _, [id, opts]}) do
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

  defp compile_state(_env, _current, [state | rest], {:repeatable, _, [step_id]}) do
    [State.add_repeatable_step(state, Step.name(step_id)) | rest]
  end

  defp compile_state(_env, _current, [state | rest], {:on_entry, _, [action]}) do
    [State.add_action(state, :entry, action) | rest]
  end

  defp compile_state(_env, _current, [state | rest], {:on_exit, _, [action]}) do
    [State.add_action(state, :exit, action) | rest]
  end

  defp compile_state(env, current, states, {:on_completed, _, [step, target]}) do
    compile_state(env, current, states, {:on, [], [{:completed, step}, target]})
  end

  defp compile_state(env, current, states, {:on_completed, _, [step, target, options]}) do
    compile_state(env, current, states, {:on, [], [{:completed, step}, target, options]})
  end

  defp compile_state(env, current, states, {:on_decision, _, [step, decision, target]}) do
    compile_state(env, current, states, {:on, [], [{:decision, step, decision}, target]})
  end

  defp compile_state(
         env,
         current,
         states,
         {:on_decision, _, [step, decision, target, options]}
       ) do
    compile_state(
      env,
      current,
      states,
      {:on, [], [{:decision, step, decision}, target, options]}
    )
  end

  defp compile_state(env, current, states, {:on_no_steps, _, [target]}) do
    compile_state(env, current, states, {:on_no_steps, [], [target, []]})
  end

  defp compile_state(env, current, states, {:on_no_steps, _, [target, options]}) do
    compile_state(env, current, states, {:on, [], [:__no_steps__, target, options]})
  end

  defp compile_state(env, current, states, {:on_final, _, [target]}) do
    compile_state(env, current, states, {:on_final, [], [target, []]})
  end

  defp compile_state(env, current, states, {:on_final, _, [target, options]}) do
    compile_state(env, current, states, {:on, [], [:__final__, target, options]})
  end

  defp compile_state(env, current, states, {:on, _, [id, target]}) do
    compile_state(env, current, states, {:on, [], [id, target, []]})
  end

  defp compile_state(_env, current, [state | rest], {:on, _, [event, target, opts]}) do
    transition = Transition.new(event, State.resolve(current, target), opts)
    [State.add_transition(state, transition) | rest]
  end

  defp compile_state(_env, _current, states, _) when is_list(states) do
    states
  end

  defp expand_subject_alias(%Chart{subject: {name, queryable}} = chart, env) do
    %Chart{chart | subject: {name, Macro.expand(queryable, env)}}
  end

  defp expand_subject_alias(chart, _env) do
    chart
  end
end
