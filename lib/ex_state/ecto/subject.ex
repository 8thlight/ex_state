defmodule ExState.Ecto.Subject do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [has_workflow: 1, has_workflow: 3]

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def workflow_association, do: elem(@ex_state_workflow, 0)
      def workflow_definition, do: elem(@ex_state_workflow, 1)
    end
  end

  defmacro has_workflow(field_name, definition, opts \\ []) do
    definition = expand_alias(definition, __CALLER__)

    quote bind_quoted: [field_name: field_name, definition: definition, opts: opts] do
      Module.put_attribute(__MODULE__, :ex_state_workflow, {field_name, definition})
      belongs_to field_name, ExState.Ecto.Workflow, Keyword.put(opts, :type, Ecto.UUID)
    end
  end

  defmacro has_workflow(definition) do
    definition = expand_alias(definition, __CALLER__)

    quote bind_quoted: [definition: definition] do
      Module.put_attribute(__MODULE__, :ex_state_workflow, {:workflow, definition})
      belongs_to :workflow, ExState.Ecto.Workflow, type: Ecto.UUID
    end
  end

  defp expand_alias({:__aliases__, _, _} = ast, env), do: Macro.expand(ast, env)
  defp expand_alias(ast, _env), do: ast

  def workflow_definition(%module{} = _subject) do
    module.workflow_definition()
  end

  def workflow_association(%module{} = _subject) do
    module.workflow_association()
  end

  def put_workflow(subject, workflow) do
    Map.put(subject, workflow_association(subject), workflow)
  end
end
