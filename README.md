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

The column is `:map` in the migration, which Postgres renders as `jsonb`:

```elixir
create table(:accounts) do
  add :settings, :map
end
```

## Why this is a separate library

Spectral already works with `jsonb` columns through its `:pre_encoded` and `:pre_decoded`
options, and that integration needs nothing from Ecto. Packaging it as a field type does:
a real Ecto dependency, a Postgres instance to test against, and its own compatibility
story as Ecto releases. Keeping it here leaves Spectral free of all three.

## Installation

```elixir
def deps do
  [
    {:ecto_spectral, "~> 0.1"}
  ]
end
```

Requires Erlang/OTP 27 or later, which is where Spectral's `json` module comes from.

Postgrex needs a JSON library configured to encode `jsonb` parameters. Phoenix projects
already have this; otherwise point it at Elixir's built-in module:

```elixir
config :postgrex, :json_library, JSON
```

## Options

| Option | | |
|---|---|---|
| `:module` | required | The module holding the type definition |
| `:type` | required | The name of the type in that module, as an atom |
| `:on_load_error` | `:raise` (default) or `:error` | What a load failure does |

## How the callbacks behave

### `nil`

`Ecto.Type` dispatches to parameterized types *before* its own `nil` shortcut, so a `NULL`
column arrives as `nil` in `cast/2`, `load/3` and `dump/3` alike. A plain `Ecto.Type` never
sees `nil`, which makes this easy to miss when porting one. All three pass it through.
A `NOT NULL` column is enforced by the database and by `validate_required/3`, not by the type.

### What `cast/2` accepts

`cast/2` takes both the native term and the external JSON document:

```elixir
Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])
```

It checks the native reading first. That order is not cosmetic. A struct is a map with atom
keys, so decoding one as a document finds none of the keys it is looking for and fills every
field from the struct defaults, which would silently replace the value you passed.

### Errors

The three callbacks differ in how much they can say.

`cast/2` returns `{:error, message: ..., spectral_errors: [%Spectral.Error{}]}`, so changeset
validation keeps the detail:

```elixir
{message, opts} = changeset.errors[:settings]
message
#=> "no_match at theme"
opts[:spectral_errors]
#=> [%Spectral.Error{location: [:theme], type: :no_match, ...}]
```

Ecto adds its own `:type` and `:validation` keys to those options.

`dump/3` can only return `:error`. Ecto turns that into an `Ecto.ChangeError` naming the
field and the value, without Spectral's error list.

`load/3` can only return `:error` too, which Ecto turns into an `ArgumentError`. A load
failure means the column already holds data that does not match the declared type, which is
a data bug rather than user input, so this type raises `EctoSpectral.LoadError` instead and
carries the full error list on the exception. Pass `on_load_error: :error` to get Ecto's
`ArgumentError` back.

### Embedded schemas

`embed_as/2` answers `:dump`, because the decoded term is a struct with atom keys and atom
values, which is not JSON on its own. A field inside an `embeds_one` or `embeds_many` is
therefore stored as its dumped document, the same shape it would have in a column of its own.

### Lists at the top level

A type whose top level is a list works without a separate field type:

```elixir
@type names :: [String.t()]
```

`type/1` still reports `:map`, which is only the name the Postgres adapter uses to pick a
dumper. The parameterized callbacks produce the value the driver encodes, so the list reaches
the column as a JSON array and `jsonb_typeof` reports `array`.

### Unions

A self-describing union, where the discriminator is a literal atom inside the document,
needs no extra wiring:

```elixir
@type shape :: Circle.t() | Square.t()
```

An `Ecto.ParameterizedType` cannot pick the type from another column, since `load/3` receives
only the column value. When the discriminator lives in a sibling column, leave the payload as
a plain `:map` and call `Spectral.decode/5` yourself. Spectral's README covers both patterns.

## Running the tests

The tests write and read actual `jsonb`, so they need a real Postgres instance:

```bash
docker compose up -d
mix test
```

`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE` override the connection. `mix test`
drops, creates and migrates the test database first.

## License

Apache-2.0
