defmodule ExState.Ecto.Model do
  defmacro __using__(opts \\ []) do
    primary_key = Keyword.get(opts, :primary_key, [])
    primary_key_type = Keyword.get(primary_key, :type, Ecto.UUID)
    autogenerate = Keyword.get(primary_key, :autogenerate, false)
    read_after_writes = !autogenerate

    quote do
      use Ecto.Schema

      @primary_key {:id, unquote(primary_key_type),
                    autogenerate: unquote(autogenerate),
                    read_after_writes: unquote(read_after_writes)}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]

      import Ecto.Changeset
      import unquote(__MODULE__)

      @type t :: %__MODULE__{}

      def new(attrs) do
        new(__MODULE__, attrs)
      end

      defoverridable new: 1
    end
  end

  def new(mod, attrs) do
    mod.changeset(struct(mod), attrs)
  end
end
