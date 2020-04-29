# ExState

[![Hex.pm](https://img.shields.io/hexpm/v/ex_state_ecto.svg)](https://hex.pm/packages/ex_state_ecto)
[![Hex Docs](https://img.shields.io/badge/hexdocs-release-blue.svg)](https://hexdocs.pm/ex_state_ecto/ExState.html)

Elixir state machines, statecharts, and workflows for Ecto models.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_state_ecto, "~> 0.2.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ex_state](https://hexdocs.pm/ex_state).

## Usage

### Without Ecto

- [Example](test/ex_state/examples/vending_machine_test.exs)

### Ecto Setup

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

```elixir
config :ex_state, ExState,
  repo: MyApp.Repo
```

### Defining States

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

  def guard_transition(:pending, :sent, %{sale: %{address: nil}}) do
    {:error, "missing address"}
  end

  def guard_transition(_from, _to, _context), do: :ok

  def update_cancelled_at(%{sale: sale}) do
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

  schema "sales" do
    has_workflow SaleWorkflow
    field :product_id, :string
    field :cancelled_at, :utc_datetime
  end
end
```

### Transitioning States

Using `ExState.transition/3`:

```elixir
def create_sale(params) do
  Multi.new()
  |> Multi.insert(:sale, Sale.new(params))
  |> ExState.Ecto.Multi.create(:sale)
  |> Repo.transaction()
end

def cancel_sale(id, user_id: user_id) do
  sale = Repo.get(Sale, id)

  ExState.transition(sale, :cancel, user_id: user_id)
end
```

Using `ExState.Execution.transition_maybe/2`:

```elixir
sale
|> ExState.create()
|> ExState.Execution.transition_maybe(:send)
|> ExState.persist()
```

Using `ExState.Execution.transition/2`:

```elixir
{:ok, execution} =
  sale
  |> ExState.load()
  |> ExState.Execution.transition(:cancelled)

ExState.persist(execution)
```

Using `ExState.Execution.transition!/2`:

```elixir
sale
|> ExState.load()
|> ExState.Execution.transition!(:cancelled)
|> ExState.persist()
```

### Completing Steps

```elixir
def acknowledge_receipt(id, user_id: user_id) do
  sale = Repo.get(Sale, id)

  ExState.complete(sale, :acknowledge_receipt, user_id: user_id)
end
```

### Running Tests

Setup test database

```bash
MIX_ENV=test mix ecto.create
mix test
```

## TODO

- Extract `ex_state_core`, and other backend / db packages.
- Multiple workflows per subject.
- Allow configurable primary key / UUID type for usage across different
  databases.
- Tracking event history with metadata.
- Add SCXML support
- Define schema for serialization / json API usage / client consumption.
- [Parallel states](https://xstate.js.org/docs/guides/parallel.html#parallel-state-nodes)
- [History states](https://xstate.js.org/docs/guides/history.html#history-state-configuration)
