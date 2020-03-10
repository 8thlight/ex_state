defmodule ExState.Definition.Typescript do
  alias ExState.Definition.Chart

  def export(chart) do
    chart
    |> Chart.describe()
    |> Enum.reduce("", fn
      {"states", states}, ts ->
        ts_union(ts, "State", states)

      {"steps", steps}, ts ->
        ts_union(ts, "Step", steps)

      {"events", events}, ts ->
        ts_union(ts, "Event", events)

      {"participants", participants}, ts ->
        ts_union(ts, "Participant", participants)
    end)
  end

  defp ts_union(ts, name, members) do
    var = ts <> "export type #{name} =\n"

    members =
      Enum.reduce(members, var, fn member, union ->
        union <> "  | '#{member}'\n"
      end)

    members <> "\n"
  end
end
