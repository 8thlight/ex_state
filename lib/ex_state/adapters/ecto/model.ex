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

  import Ecto.Changeset

  def new(mod, attrs) do
    mod.changeset(struct(mod), attrs)
  end

  def put_assoc_maybe(changeset, assoc, attrs, transform) do
    case Map.fetch(attrs, assoc) do
      :error ->
        changeset

      {:ok, nil} ->
        put_assoc(changeset, assoc, nil)

      {:ok, assoc_attrs} ->
        case transform_assoc(assoc_attrs, transform) do
          {:ok, transformed} ->
            put_assoc(changeset, assoc, transformed)

          {:error, %Ecto.Changeset{} = changeset} ->
            add_error(changeset, assoc, get_error(changeset))

          {:error, reason} ->
            add_error(changeset, assoc, reason)
        end
    end
  end

  defp get_error(changeset) do
    changeset
    |> traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map(fn {k, v} -> "#{k} #{v}" end)
    |> Enum.join(",")
  end

  defp transform_assoc(attrs, transform) when is_list(attrs) do
    Enum.reduce(attrs, {:ok, []}, fn
      next, {:ok, transformed} ->
        case transform_assoc(next, transform) do
          {:ok, value} ->
            {:ok, transformed ++ [value]}

          e ->
            e
        end

      _, e ->
        e
    end)
  end

  defp transform_assoc(attrs, transform) do
    transform.(attrs)
  end
end
