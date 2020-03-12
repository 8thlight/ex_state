defmodule ExState.Result do
  def get({:ok, result}), do: result

  def map({:ok, result}, f), do: {:ok, f.(result)}
  def map(e, _), do: e

  def flat_map({:ok, result}, f), do: f.(result)
  def flat_map(e, _), do: e

  defmodule Multi do
    def extract({:ok, result}, key) do
      {:ok, Map.get(result, key)}
    end

    def extract({:error, _, reason, _}, _key) do
      {:error, reason}
    end
  end
end
