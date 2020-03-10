defmodule ExState.Definition.Step do
  @type t :: %__MODULE__{
          name: String.t(),
          participant: atom(),
          order: integer(),
          complete?: boolean(),
          decision: atom()
        }

  defstruct name: nil, participant: nil, order: 1, complete?: false, decision: nil

  def new(id, participant) do
    %__MODULE__{name: name(id), participant: participant}
  end

  def order(s, o) do
    %__MODULE__{s | order: o}
  end

  def complete(s, decision \\ nil) do
    %__MODULE__{s | complete?: true, decision: decision}
  end

  def name(id) when is_atom(id), do: Atom.to_string(id)
  def name(id) when is_bitstring(id), do: id

  # The atom may not exist due to being converted to string at compile time.
  # Should be safe to use to_atom here since the workflows API shouldn't be
  # exposed to external input.
  def id(step), do: String.to_atom(step.name)
end
