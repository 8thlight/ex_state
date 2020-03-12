defmodule ExState.Ecto.Multi do
  alias ExState
  alias Ecto.Multi

  @spec create(Multi.t(), struct() | atom()) :: Multi.t()
  def create(%Multi{} = multi, subject_key) when is_atom(subject_key) do
    Multi.merge(multi, fn results ->
      ExState.create_multi(Map.get(results, subject_key))
    end)
  end

  def create(%Multi{} = multi, subject) do
    Multi.merge(multi, fn _ ->
      ExState.create_multi(subject)
    end)
  end

  @spec transition(Multi.t(), struct() | atom(), any(), keyword()) :: Multi.t()
  def transition(multi, subject_or_key, event, opts \\ [])

  def transition(%Multi{} = multi, subject_key, event, opts) when is_atom(subject_key) do
    Multi.run(multi, event, fn _repo, results ->
      ExState.transition(Map.get(results, subject_key), event, opts)
    end)
  end

  def transition(%Multi{} = multi, subject, event, opts) do
    Multi.run(multi, event, fn _repo, _ ->
      ExState.transition(subject, event, opts)
    end)
  end

  @spec complete(Multi.t(), struct() | atom(), any(), keyword()) :: Multi.t()
  def complete(multi, subject_or_key, step_id, opts \\ [])

  def complete(%Multi{} = multi, subject_key, step_id, opts) when is_atom(subject_key) do
    Multi.run(multi, step_id, fn _repo, results ->
      ExState.complete(Map.get(results, subject_key), step_id, opts)
    end)
  end

  def complete(%Multi{} = multi, subject, step_id, opts) do
    Multi.run(multi, step_id, fn _repo, _ ->
      ExState.complete(subject, step_id, opts)
    end)
  end

  @spec decision(Multi.t(), struct() | atom(), any(), any(), keyword()) :: Multi.t()
  def decision(multi, subject_or_key, step_id, decision, opts \\ [])

  def decision(%Multi{} = multi, subject_key, step_id, decision, opts)
      when is_atom(subject_key) do
    Multi.run(multi, step_id, fn _repo, results ->
      ExState.decision(Map.get(results, subject_key), step_id, decision, opts)
    end)
  end

  def decision(%Multi{} = multi, subject, step_id, decision, opts) do
    Multi.run(multi, step_id, fn _repo, _ ->
      ExState.decision(subject, step_id, decision, opts)
    end)
  end
end
