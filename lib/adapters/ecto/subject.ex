defmodule ExState.Ecto.Subject do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def workflow_definition, do: @workflow_definition
      def workflow_assoc_name, do: @workflow_assoc_name
    end
  end

  defmacro has_workflow(field_name, definition, opts \\ []) do
    definition = expand_alias(definition, __CALLER__)

    quote bind_quoted: [field_name: field_name, definition: definition, opts: opts] do
      Module.put_attribute(__MODULE__, :workflow_definition, definition)
      Module.put_attribute(__MODULE__, :workflow_assoc_name, field_name)
      belongs_to field_name, ExState.Workflow, opts
    end
  end

  defmacro has_workflow(definition) do
    definition = expand_alias(definition, __CALLER__)

    quote do
      Module.put_attribute(__MODULE__, :workflow_definition, unquote(definition))
      Module.put_attribute(__MODULE__, :workflow_assoc_name, :workflow)
      belongs_to :workflow, ExState.Workflow
    end
  end

  defp expand_alias({:__aliases__, _, _} = ast, env), do: Macro.expand(ast, env)
  defp expand_alias(ast, _env), do: ast

  def workflow_definition(%module{} = _subject) do
    module.workflow_definition()
  end

  def workflow_assoc_name(%module{} = _subject) do
    module.workflow_assoc_name()
  end
end
