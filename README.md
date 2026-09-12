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

## How the callbacks behave

### `nil`

`Ecto.Type` dispatches to parameterized types *before* its own `nil` shortcut, so a `NULL`
column arrives as `nil` in `cast/2`, `load/3` and `dump/3` alike. A plain `Ecto.Type` never
sees `nil`, which makes this easy to miss when porting one. All three pass it through.
A `NOT NULL` column is enforced by the database and by `validate_required/3`, not by the type.

A `jsonb` document that is itself `null` is a separate thing from a SQL `NULL`, but not by
the time it reaches `load/3`: the driver decodes both to `nil`. Such a row loads as `nil`
without being checked against the type, and writing the field replaces it with a real `NULL`.

### What `cast/2` accepts

`cast/2` takes both the native term and the external JSON document:

```elixir
Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])
```

Which reading it uses comes down to shape. A `jsonb` column can only hand back an object with
string keys, an array, a string, a number, a boolean or null, so a value carrying a struct, an
atom key or an atom value anywhere inside it can only be a term of the type, and the document
reading is not tried at all. That matters because reading such a value as a document matches
none of its keys and fills every field from the type's defaults, which would silently replace
what you passed.

When the value could be either, and both readings claim it, the answer is the one `load/3`
would give. Some types accept the same value both ways while meaning different things by it:
with `:dark | String.t()`, `"dark"` is a valid `String.t()` and also the encoding of `:dark`.
Otherwise `cast/2` would keep the string, `load/3` would answer `:dark`, and the field would
report a change on every save.

Nothing is re-encoded on the way through, so a type that exposes only some of its struct's
fields still casts to the whole struct. The fields it does not expose are dropped by `dump/3`,
where the type says they should be.

Neither `cast/2` nor `load/3` is stricter than the type. Spectral ignores document keys the
type does not mention and fills omitted fields from the struct defaults, so a form posting
`settings[them]` instead of `settings[theme]` casts to the defaults rather than failing, and a
stored document with no keys in common with the type loads as the defaults rather than
raising. What `load/3` catches is a key that is present and wrong, not a document that is
simply unrelated. Put anything the type does not express into `Ecto.Changeset` validations.

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

One case is worth knowing before relying on that. Postgres stores `jsonb` numbers as
`numeric`, which drops exponent notation, so a `float()` of `1.0e10` reads back as the
integer `10000000000` and stops matching `float()`. A column holding large-magnitude floats
can fail to load data this type itself wrote. `on_load_error: :error` only changes which
exception you get.

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

## Scope

Tested against Postgres, where `:map` means `jsonb` and the adapter hands the dumped value
to the driver untouched. Other adapters make their own arrangements for `:map` and are
neither tested nor supported.

`{:array, EctoSpectral.JSONB}` works against a column declared `add :col, {:array, :map}`.
Ecto dumps the elements one at a time and Postgres stores them as a real `jsonb[]`. Point it
at a plain `jsonb` column by mistake and the list is stored as a single JSON array instead,
which round trips but is not what the field says it is.

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
