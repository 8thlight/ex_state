# ExState

Elixir state charts and workflows for Ecto models.

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
defmodule SaleWorkflow do
  use ExState.Definition

  alias MyApp.Repo

  workflow "sale" do
    subject :sale, Sale

    participant :seller
    participant :buyer

    initial_state :pending

    state :pending do
      on :send, :sent
      on :cancel, :cancelled
    end

    state :sent do
      parallel do
        step :acknowledge_receipt, participant: :buyer
        step :close, participant: :seller
      end

      on :cancelled, :cancelled
      on_completed :acknowledge_receipt, :receipt_acknowledged
      on_completed :close, :closed
    end

    state :receipt_acknowledged do
      step :close, participant: :seller
      on_completed :close, :closed
    end

    state :closed

    state :cancelled do
      on_entry :update_cancelled_at
    end
  end

  def update_cancelled_at(sale) do
    sale
    |> Sale.changeset(%{cancelled_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
```

```elixir
defmodule Sale do
  use Ecto.Schema
  use ExState.Ecto.Subject

  import Ecto.Changeset

  alias ExState.TestSupport.User

  schema "sales" do
    has_workflow SaleWorkflow
    field :product_id, :string
    field :cancelled_at, :utc_datetime
  end
end
```

```elixir
sale
|> ExState.create()
|> ExState.Execution.transition(:send)
|> ExState.persist()
```

```elixir
sale
|> ExState.load()
|> ExState.Execution.transition(:cancelled)
|> ExState.persist()
```

```elixir
def create_sale(params) do
  Multi.new()
  |> Multi.insert(:sale, Sale.new(params))
  |> ExState.Ecto.Multi.create(:sale)
  |> Repo.transaction()
end

def cancel_sale(id) do
  sale = Repo.get(Sale, id)

  ExState.transition(sale, :cancel)
end
```

## TODO

- Multiple workflows per subject.
- Allow configurable primary key / UUID type for usage across different
  databases.
- Allow configurable user / participant entity type and association.
