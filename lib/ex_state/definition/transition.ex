defmodule ExState.Definition.Transition do
  @type event :: atom() | {:completed, atom()} | {:decision, atom(), atom()}

  @type t :: %__MODULE__{
          event: event(),
          reset: boolean(),
          target: String.t() | [String.t()],
          actions: [atom()]
        }

  defstruct event: nil, reset: true, target: nil, actions: []

  def new(event, target, opts \\ []) do
    reset = Keyword.get(opts, :reset, true)
    action = Keyword.get(opts, :action, nil)
    actions = if action, do: [action], else: Keyword.get(opts, :actions, [])

    %__MODULE__{
      event: event,
      target: target,
      actions: actions,
      reset: reset
    }
  end
end
