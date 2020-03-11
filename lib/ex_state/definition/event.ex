defmodule ExState.Definition.Event do
  @type name :: atom() | {:completed, atom()} | {:decision, atom(), atom()}

  @type t :: %__MODULE__{
          name: name(),
          reset: boolean(),
          next_state: String.t(),
          actions: [atom()]
        }

  defstruct name: nil, reset: true, next_state: nil, actions: []

  def new(name, next_state, opts \\ []) do
    reset = Keyword.get(opts, :reset, true)
    action = Keyword.get(opts, :action, nil)
    actions = if action, do: [action], else: Keyword.get(opts, :actions, [])

    %__MODULE__{
      name: name,
      next_state: next_state,
      actions: actions,
      reset: reset
    }
  end
end
