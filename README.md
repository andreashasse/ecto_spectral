# EctoSpectral

An `Ecto.ParameterizedType` that stores [Spectral](https://github.com/andreashasse/spectral)-typed
values in `jsonb` columns.

```elixir
defmodule MyApp.Settings do
  use Spectral

  defstruct theme: :light, notifications: true, locale: nil

  @type t :: %__MODULE__{
          theme: :light | :dark,
          notifications: boolean(),
          locale: String.t() | nil
        }
end

defmodule MyApp.Account do
  use Ecto.Schema

  schema "accounts" do
    field :settings, EctoSpectral.JSONB, module: MyApp.Settings, type: :t
  end
end
```

```elixir
Repo.insert!(%MyApp.Account{settings: %MyApp.Settings{theme: :dark}})
Repo.one!(MyApp.Account).settings
#=> %MyApp.Settings{theme: :dark, notifications: true, locale: nil}
```

The migration names the database type, not `EctoSpectral.JSONB`. Use `:map`, which Postgres
renders as `jsonb`, or `:jsonb` directly:

```elixir
defmodule MyApp.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :settings, :map
    end
  end
end
```

## Why use it

Spectral can already turn a `jsonb` document into a typed value and back. Without this
library the column is a plain `:map`, and every function that reads or writes it has to call
Spectral itself:

```elixir
# field :settings, :map

def put_settings(account, settings) do
  {:ok, document} = Spectral.encode(settings, MyApp.Settings, :t, :json, [:pre_encoded])
  Ecto.Changeset.change(account, settings: document)
end

def get_settings(account) do
  {:ok, settings} =
    Spectral.decode(account.settings, MyApp.Settings, :t, :json, [:pre_decoded])

  settings
end
```

Every read and write path has to remember those calls, the schema struct holds a raw map, and
a document that does not match the type surfaces as a match error instead of a changeset
error. With `EctoSpectral.JSONB` the field holds the typed value itself. Ecto encodes it on
insert and update, decodes it on load, and validates it in `cast/3`.

It is a separate library rather than part of Spectral because it needs a real Ecto dependency
and a Postgres instance to test against.

## Installation

```elixir
def deps do
  [
    {:ecto_spectral, "~> 0.1"}
  ]
end
```

Requires Erlang/OTP 27 or later, which is what Spectral itself requires.

Postgrex needs a JSON library configured to encode `jsonb` parameters. Phoenix projects
already have this; otherwise point it at Elixir's built-in module:

```elixir
config :postgrex, :json_library, JSON
```

## Options

| Option | | |
|---|---|---|
| `:module` | required | The module holding the type definition |
| `:type` | required | The name of the type in that module, as an atom, or a Spectral type reference such as `{:type, :t, 0}` to pick between types sharing a name |
| `:on_load_error` | `:raise` (default) or `:error` | What a load failure does |

Anything else is rejected, apart from the options `Ecto.Schema` itself adds to a field. A
typo in `:on_load_error` is a compile-time error rather than a silent default.

## Behaviour

### `nil`

A `NULL` column loads as `nil`, and `nil` is written as `NULL`. `NOT NULL` is enforced by the
database and by `validate_required/3`, not by the type.

A `jsonb` document that is itself `null` also loads as `nil`, without being checked against
the type, and writing the field replaces it with a real `NULL`.

### Casting

`cast/3` takes both the typed value your own code builds and the string-keyed document a
controller or a form sends:

```elixir
Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])
Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
```

A value containing a struct, an atom key or an atom value is taken as the typed value and
kept as it is. Anything else is decoded as a document.

- **A misspelled key is not an error.** Spectral ignores keys the type does not mention and
  fills missing fields from the struct defaults, so `%{"them" => "dark"}` casts to the
  defaults. A stored document with nothing in common with the type likewise loads as the
  defaults. Validate anything the type does not express with `Ecto.Changeset`.
- **Fields a type leaves out survive until the row is written.** A type using Spectral's
  `only` still casts to the whole struct, and the excluded fields are dropped on write.
- **A value valid both ways reads as it will after a reload.** With `:dark | String.t()`,
  casting `"dark"` gives `:dark`, the same as loading it.

### Errors

An invalid value in a changeset keeps Spectral's detail:

```elixir
{message, opts} = changeset.errors[:settings]
message
#=> "no_match at theme"
opts[:spectral_errors]
#=> [%Spectral.Error{location: [:theme], type: :no_match, ...}]
```

Ecto adds its own `:type` and `:validation` keys to those options.

Writing a value that does not match the type, without going through a changeset, raises
`Ecto.ChangeError` naming the field and the value.

Loading a row whose document does not match the type raises `EctoSpectral.LoadError`, which
carries Spectral's error list. Data already in the column that does not match its type is a
bug rather than user input. Pass `on_load_error: :error` to get Ecto's own `ArgumentError`
instead, which names the field but not the reason.

Postgres stores `jsonb` numbers as `numeric`, which drops exponent notation, so a `float()`
of `1.0e10` reads back as the integer `10000000000` and stops matching `float()`. A column
holding large-magnitude floats can fail to load data this type itself wrote.
`on_load_error: :error` only changes which exception you get.

### Embedded schemas

The type works inside `embeds_one` and `embeds_many`. The field is stored as the same
document it would be in a column of its own.

### Top-level values that are not objects

The type does not have to describe an object. `jsonb` holds any JSON value:

```elixir
@type names :: [String.t()]          # stored as ["a", "b"]
@type tags :: [Tag.t()]              # stored as [{"name": ...}, ...]
@type mode :: :dark | String.t()     # stored as "dark"
```

### Types that take a parameter

A type with a parameter cannot be named as the field type, because nothing can supply the
argument, and it raises on first use. Define a concrete alias and name that instead:

```elixir
@type box(value) :: %{value: value}
@type int_box :: box(integer())

field :count, EctoSpectral.JSONB, module: MyApp.Types, type: :int_box
```

### Unions

A self-describing union, where the discriminator is a literal atom inside the document,
needs no extra wiring:

```elixir
@type shape :: Circle.t() | Square.t()
```

A field cannot pick its type from another column. When the discriminator lives in a sibling
column, leave the payload as a plain `:map` and call `Spectral.decode/5` yourself. Spectral's
README covers both patterns.

## Scope

Tested against Postgres only. Other adapters are neither tested nor supported.

`{:array, EctoSpectral.JSONB}` works against a column declared `add :col, {:array, :map}`,
which Postgres stores as a `jsonb[]` with one document per element. Against a plain `jsonb`
column the list is stored as a single JSON array instead, which round trips but is not what
the field says it is.

## Running the tests

The tests write and read actual `jsonb`, so they need a real Postgres instance:

```bash
make db
make test
```

`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE` override the connection, and
`make db` publishes the container on `PGPORT` so an existing Postgres on 5432 does not get in
the way. `mix test` creates and migrates the test database first.

`make ci` runs everything CI runs: compile, tests, Credo, Dialyzer, formatting, `mix docs` and
`mix hex.build`. `make format` rewrites files, `make shell` opens IEx, and `make db_stop`
takes the container down.

## License

Apache-2.0
