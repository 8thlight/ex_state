defmodule ExState do
  import Ecto.Query
  import ExState.Ecto.Query

  alias Ecto.Multi
  alias Ecto.Changeset
  alias ExState.Ecto.Workflow
  alias ExState.Ecto.WorkflowStep
  alias ExState.Ecto.WorkflowParticipant
  alias ExState.Ecto.Subject
  alias ExState.Result
  alias ExState.Definition.Execution

  def repo do
    :ex_state
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:repo)
  end

  @spec get(struct()) :: Workflow.t() | nil
  def get(subject) do
    subject
    |> Ecto.assoc(Subject.workflow_assoc_name(subject))
    |> preload(participants: [], steps: :participant)
    |> repo().one()
    |> put_definition(subject)
  end

  defp put_definition(nil, _subject), do: nil

  defp put_definition(workflow, subject) do
    Map.put(workflow, :definition, Subject.workflow_definition(subject))
  end

  @spec state(module(), any()) :: [atom()]
  def state(subject_type, subject_id) do
    subject_type
    |> where([s], s.id == ^subject_id)
    |> join(:inner, [s], w in assoc(s, ^subject_type.workflow_assoc_name()))
    |> select([s, w], w.state)
    |> repo().one()
    |> to_state_list()
  end

  @spec state(struct()) :: [atom()]
  def state(subject) do
    subject
    |> Ecto.assoc(Subject.workflow_assoc_name(subject))
    |> select([w], w.state)
    |> repo().one()
    |> to_state_list()
  end

  @type state :: atom() | String.t() | [atom()] | [String.t()]

  @spec state?(struct(), state()) :: boolean()
  def state?(subject, state) do
    subject
    |> Ecto.assoc(Subject.workflow_assoc_name(subject))
    |> where([w], w.state == ^to_state_id(state))
    |> repo().exists?()
  end

  @spec state?(struct(), state(), keyword()) :: boolean()
  def state?(subject, state, complete: completed_steps) do
    step_names = Enum.map(completed_steps, &to_step_name/1)

    subject
    |> Ecto.assoc(Subject.workflow_assoc_name(subject))
    |> join(:inner, [w], s in WorkflowStep,
      on:
        s.workflow_id == w.id and
          s.state == w.state and
          s.name in ^step_names and
          s.complete?
    )
    |> where([w], w.state == ^to_state_id(state))
    |> repo().exists?()
  end

  def state?(subject, state, incomplete: incompleted_steps) do
    step_names = Enum.map(incompleted_steps, &to_step_name/1)

    subject
    |> Ecto.assoc(Subject.workflow_assoc_name(subject))
    |> join(:inner, [w], s in WorkflowStep,
      on:
        s.workflow_id == w.id and
          s.state == w.state and
          s.name in ^step_names and
          not s.complete?
    )
    |> where([w], w.state == ^to_state_id(state))
    |> repo().exists?()
  end

  @spec get_step(struct(), atom() | String.t()) :: WorkflowStep.t() | nil
  def get_step(subject, step) do
    subject
    |> Ecto.assoc([Subject.workflow_assoc_name(subject), :steps])
    |> where([s], s.name == ^to_step_name(step))
    |> repo().one()
  end

  @spec create(struct()) :: {:ok, %{workflow: Workflow.t()}} | {:error, any(), any(), any()}
  def create(subject) do
    create_multi(subject)
    |> repo().transaction()
  end

  @spec create_multi(struct()) :: Multi.t()
  def create_multi(subject) do
    Multi.new()
    |> Multi.insert(:workflow, create_changeset(subject))
    |> Multi.run(:subject, fn _repo, %{workflow: workflow} ->
      assoc_workflow(subject, workflow)
    end)
  end

  defp assoc_workflow(%queryable{} = subject, workflow) do
    subject
    |> queryable.changeset(%{workflow_id: workflow.id})
    |> repo().update()
  end

  @type execution_result :: {:ok, Workflow.t()} | {:error, any()}

  @spec event(struct(), any(), keyword()) :: execution_result()
  def event(subject, event, opts \\ []) do
    execute(subject, opts, fn execution ->
      Execution.transition_result(execution, event)
    end)
  end

  @spec complete(struct(), any(), keyword()) :: execution_result()
  def complete(subject, step_id, opts \\ []) do
    execute(subject, opts, fn execution ->
      Execution.complete(execution, step_id)
    end)
  end

  @spec decision(struct(), any(), any(), keyword()) :: execution_result()
  def decision(subject, step_id, decision, opts \\ []) do
    execute(subject, opts, fn execution ->
      Execution.decision(execution, step_id, decision)
    end)
  end

  @type execution_operation ::
          (Execution.t() -> {:ok, Execution.t()} | {:error, any(), Execution.t()})
  @spec execute(struct(), keyword(), execution_operation()) :: execution_result()
  def execute(subject, opts, operation) do
    case get(subject) do
      nil ->
        {:error, :no_workflow}

      workflow ->
        execution = Execution.continue(workflow.definition, subject, workflow.state)

        completed_steps = Workflow.completed_steps(workflow)

        execution =
          Enum.reduce(completed_steps, execution, fn step, execution ->
            Execution.with_completed(execution, step.state, step.name, step.decision)
          end)

        case operation.(execution) do
          {:ok, execution} ->
            complete_execution(workflow, execution, opts)

          {:error, reason, _execution} ->
            {:error, reason}
        end
    end
  end

  defp complete_execution(workflow, execution, opts) do
    Multi.new()
    |> Multi.run(:workflow, fn _repo, _ ->
      update_workflow(workflow, execution, opts)
    end)
    |> Multi.append(execute_actions(execution))
    |> repo().transaction()
    |> Result.Multi.extract(:workflow)
  end

  defp execute_actions(execution) do
    Enum.reduce(Enum.reverse(execution.actions), Multi.new(), fn action, multi ->
      Multi.run(multi, action, fn _, _ ->
        case Execution.execute_action(execution, action) do
          :ok -> {:ok, nil}
          result -> result
        end
      end)
    end)
  end

  defp update_workflow(workflow, execution, opts) do
    workflow
    |> update_changeset(execution, opts)
    |> repo().update()
  end

  defp create_changeset(subject) do
    params =
      Subject.workflow_definition(subject)
      |> Execution.new(subject)
      |> Execution.dump()
      |> put_subject()

    Workflow.new(params)
    |> Workflow.put_participants(params, &find_or_create_participant/1)
    |> Changeset.cast_assoc(:steps,
      required: true,
      with: fn step, params ->
        step
        |> WorkflowStep.changeset(params)
        |> WorkflowStep.put_participant(params, &find_or_create_participant/1)
      end
    )
  end

  defp update_changeset(workflow, execution, opts) do
    params =
      execution
      |> Execution.dump()
      |> put_subject()
      |> put_existing_step_ids(workflow)

    workflow
    |> Workflow.changeset(params)
    |> Workflow.put_participants(params, &find_or_create_participant/1)
    |> Changeset.cast_assoc(:steps,
      required: true,
      with: fn step, params ->
        step
        |> WorkflowStep.changeset(params)
        |> WorkflowStep.put_participant(params, &find_or_create_participant/1)
        |> WorkflowStep.put_completion(opts)
      end
    )
  end

  defp put_subject(params) do
    Map.update(params, :subject, nil, fn
      nil -> nil
      {name, _subject} -> Atom.to_string(name)
      name -> Atom.to_string(name)
    end)
  end

  defp put_existing_step_ids(params, workflow) do
    Map.update(params, :steps, [], fn steps ->
      Enum.map(steps, fn step -> put_existing_step_id(step, workflow.steps) end)
    end)
  end

  defp put_existing_step_id(step, existing_steps) do
    Enum.find(existing_steps, fn existing_step ->
      step.state == existing_step.state and step.name == existing_step.name
    end)
    |> case do
      nil ->
        step

      existing_step ->
        Map.put(step, :id, existing_step.id)
    end
  end

  defp find_or_create_participant(params) do
    %{
      name: Atom.to_string(params.name),
      entity_id: params.id
    }
    |> WorkflowParticipant.new()
    |> repo().insert(
      on_conflict: {:replace_all_except, [:id]},
      conflict_target: [:name, :entity_id]
    )
  end
end
