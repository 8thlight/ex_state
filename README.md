# ExState

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_state, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ex_state](https://hexdocs.pm/ex_state).

## Usage with Ecto

```elixir
defmodule MyApp.Repo.Migrations.AddWorkflows do
  def up do
    # Ensure Ecto.UUID support is enabled:
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    ExState.Ecto.Migration.up()
  end

  def down do
  end
end
```

## Usage

```elixir
sale
|> SaleWorkflow.new()
|> SaleWorkflow.event(:send)
|> ExState.persist()
```

```elixir
sale
|> ExState.load()
|> SaleWorkflow.event(:send)
|> ExState.persist()
```
