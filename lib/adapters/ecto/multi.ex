defmodule ExState.Ecto.Multi do
  alias Ecto.Multi
  alias ExState

  @spec create(Multi.t(), any()) :: Multi.t()
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

  @spec event(Multi.t(), any(), any(), keyword()) :: Multi.t()
  def event(multi, subject_or_key, event, opts \\ [])

  def event(%Multi{} = multi, subject_key, event, opts) when is_atom(subject_key) do
    Multi.run(multi, event, fn _repo, results ->
      ExState.event(Map.get(results, subject_key), event, opts)
    end)
  end

  def event(%Multi{} = multi, subject, event, opts) do
    Multi.run(multi, event, fn _repo, _ ->
      ExState.event(subject, event, opts)
    end)
  end

  @spec complete(Multi.t(), any(), any(), keyword()) :: Multi.t()
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

  @type complete_condition :: ExState.state() | (struct() -> boolean())
  @spec complete_when(Multi.t(), complete_condition(), any(), any(), keyword()) :: Multi.t()
  def complete_when(multi, condition, subject_or_key, step_id, opts \\ [])

  def complete_when(%Multi{} = multi, condition, subject_key, step_id, opts)
      when is_atom(subject_key) do
    Multi.run(multi, step_id, fn _repo, results ->
      subject = Map.get(results, subject_key)

      if should_complete?(subject, condition) do
        ExState.complete(subject, step_id, opts)
      else
        {:ok, nil}
      end
    end)
  end

  def complete_when(%Multi{} = multi, condition, subject, step_id, opts) do
    Multi.run(multi, step_id, fn _repo, _ ->
      if should_complete?(subject, condition) do
        ExState.complete(subject, step_id, opts)
      else
        {:ok, nil}
      end
    end)
  end

  defp should_complete?(subject, condition) when is_function(condition, 1) do
    condition.(subject)
  end

  defp should_complete?(subject, state) do
    ExState.state?(subject, state)
  end

  @spec decision(Multi.t(), any(), any(), any(), keyword()) :: Multi.t()
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
