defmodule ExState.Result do
  defmodule Multi do
    def extract({:ok, result}, key) do
      {:ok, Map.get(result, key)}
    end

    def extract({:error, _, reason, _}, _key) do
      {:error, reason}
    end
  end
end
