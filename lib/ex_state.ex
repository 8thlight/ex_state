defmodule ExState do
  @moduledoc """
  `ExState` loads and persists workflow execution to a database through Ecto.

  The `ExState.Execution` is built through the subject's `:workflow`
  association.

  ## Setup

      defmodule ShipmentWorkflow do
        use ExState.Definition

        workflow "shipment" do
          subject :shipment, Shipment

          initial_state :preparing

          state :preparing do
            state :packing do
              on :packed, :sealing
            end

            state :sealing do
              on :unpack, :packing
              on :sealed, :sealed
            end

            state :sealed do
              final
            end

            on_final :shipping
          end

          state :shipping do
            on :shipped, :in_transit
          end

          state :in_transit do
            on :arrival, :arrived
          end

          state :arrived od
            on :accepted, :complete
            on :return, :returning
          end

          state :returning do
            on :arrival, :returned
          end

          state :returned do
            on :replace, :preparing
          end

          state :complete do
            final
          end
        end
      end

      defmodule Shipment do
        use Ecto.Schema
        use ExState.Ecto.Subject

        schema "shipments" do
          has_workflow ShipmentWorkflow
        end
      end

  ## Creating

      sale = %Sale{id: 1}

      execution = ExState.create(sale) #=> %ExState.Execution{}

  ## Updating

      sale = %Sale{id: 1}

      {:ok, sale} =
        sale
        |> ExState.load()
        |> ExState.Execution.transition!(:packed)
        |> ExState.Execution.transition!(:sealed)
        |> ExState.persist()

      sale.workflow.state #=> "shipping"

      {:error, reason} = ExState.transition(sale, :return)
      reason #=> "no transition from state shipping for event :return"
  """

  import Ecto.Query

  alias ExState.Execution
  alias ExState.Result
  alias ExState.Ecto.Workflow
  alias ExState.Ecto.WorkflowStep
  alias ExState.Ecto.Subject
  alias Ecto.Multi
  alias Ecto.Changeset

  defp repo do
    :ex_state
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:repo)
  end

  @spec create(struct()) :: {:ok, Execution.t()} | {:error, any()}
  def create(subject) do
    create_multi(subject)
    |> repo().transaction()
    |> Result.Multi.extract(:subject)
    |> Result.map(&load/1)
  end

  @spec create!(struct()) :: Execution.t()
  def create!(subject) do
    create(subject) |> Result.get()
  end

  @spec create_multi(struct()) :: Multi.t()
  def create_multi(%queryable{} = subject) do
    Multi.new()
    |> Multi.insert(:workflow, create_changeset(subject))
    |> Multi.run(:subject, fn _repo, %{workflow: workflow} ->
      subject
      |> queryable.changeset(%{workflow_id: workflow.id})
      |> repo().update()
      |> Result.map(&Subject.put_workflow(&1, workflow))
    end)
  end

  @spec load(struct()) :: Execution.t() | nil
  def load(subject) do
    with workflow when not is_nil(workflow) <- get(subject),
         definition <- Subject.workflow_definition(subject),
         execution <- Execution.continue(definition, workflow.state),
         execution <- Execution.put_subject(execution, subject),
         execution <- with_completed_steps(execution, workflow),
         execution <- Execution.with_meta(execution, :workflow, workflow) do
      execution
    end
  end

  defp get(subject) do
    subject
    |> Ecto.assoc(Subject.workflow_association(subject))
    |> preload(:steps)
    |> repo().one()
  end

  defp with_completed_steps(execution, workflow) do
    completed_steps = Workflow.completed_steps(workflow)

    Enum.reduce(completed_steps, execution, fn step, execution ->
      Execution.with_completed(execution, step.state, step.name, step.decision)
    end)
  end

  @spec transition(struct(), any(), keyword()) :: {:ok, struct()} | {:error, any()}
  def transition(subject, event, opts \\ []) do
    load(subject)
    |> Execution.with_meta(:opts, opts)
    |> Execution.transition(event)
    |> map_execution_error()
    |> Result.flat_map(&persist/1)
  end

  @spec complete(struct(), any(), keyword()) :: {:ok, struct()} | {:error, any()}
  def complete(subject, step_id, opts \\ []) do
    load(subject)
    |> Execution.with_meta(:opts, opts)
    |> Execution.complete(step_id)
    |> map_execution_error()
    |> Result.flat_map(&persist/1)
  end

  @spec decision(struct(), any(), any(), keyword()) :: {:ok, struct()} | {:error, any()}
  def decision(subject, step_id, decision, opts \\ []) do
    load(subject)
    |> Execution.with_meta(:opts, opts)
    |> Execution.decision(step_id, decision)
    |> map_execution_error()
    |> Result.flat_map(&persist/1)
  end

  defp map_execution_error({:error, reason, _execution}), do: {:error, reason}
  defp map_execution_error(result), do: result

  @spec persist(Execution.t()) :: {:ok, struct()} | {:error, any()}
  def persist(execution) do
    actions_multi =
      Enum.reduce(Enum.reverse(execution.actions), Multi.new(), fn action, multi ->
        Multi.run(multi, action, fn _, _ ->
          case Execution.execute_action(execution, action) do
            {:ok, execution, result} -> {:ok, {execution, result}}
            e -> e
          end
        end)
      end)

    Multi.new()
    |> Multi.run(:workflow, fn _repo, _ ->
      workflow = Map.fetch!(execution.meta, :workflow)
      opts = Map.get(execution.meta, :opts, [])
      update_workflow(workflow, execution, opts)
    end)
    |> Multi.append(actions_multi)
    |> repo().transaction()
    |> case do
      {:ok, %{workflow: workflow} = results} ->
        actions_multi
        |> Multi.to_list()
        |> List.last()
        |> case do
          nil ->
            {:ok, Subject.put_workflow(Execution.get_subject(execution), workflow)}

          {action, _} ->
            case Map.get(results, action) do
              nil ->
                {:ok, Subject.put_workflow(Execution.get_subject(execution), workflow)}

              {execution, _} ->
                {:ok, Subject.put_workflow(Execution.get_subject(execution), workflow)}
            end
        end

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp update_workflow(workflow, execution, opts) do
    workflow
    |> update_changeset(execution, opts)
    |> repo().update()
  end

  defp create_changeset(subject) do
    params =
      Subject.workflow_definition(subject)
      |> Execution.new()
      |> Execution.put_subject(subject)
      |> Execution.dump()

    Workflow.new(params)
    |> Changeset.cast_assoc(:steps,
      required: true,
      with: fn step, params ->
        step
        |> WorkflowStep.changeset(params)
      end
    )
  end

  defp update_changeset(workflow, execution, opts) do
    params =
      execution
      |> Execution.dump()
      |> put_existing_step_ids(workflow)

    workflow
    |> Workflow.changeset(params)
    |> Changeset.cast_assoc(:steps,
      required: true,
      with: fn step, params ->
        step
        |> WorkflowStep.changeset(params)
        |> WorkflowStep.put_completion(Enum.into(opts, %{}))
      end
    )
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
end
