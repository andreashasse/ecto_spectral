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

`:map` is Ecto's name for the column; Postgres renders it as `jsonb`:

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

## Which callback goes which way

A `jsonb` column never hands Elixir a JSON string. The driver does its own serialization, so
the callbacks meet it already parsed.

| | Runs | Direction |
|---|---|---|
| `dump/3` | on the way to the column | encodes a term of the type into what the driver serializes |
| `load/3` | on the way back | decodes the document the driver parsed into a term of the type |
| `cast/2` | on the way in from outside | decodes too, despite its result being bound for the column |

`cast/2` is not the encoding step. `dump/3` is, and it runs later. These are Spectral's
`:pre_encoded` and `:pre_decoded` options exactly.

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

`cast/2` is handed two different kinds of value, depending on who is calling. A controller or
a form sends a **document**: string keys, string values, straight from JSON. Your own code
sends a **term**: the struct or map the type describes. Both work:

```elixir
Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])
```

A document has to be decoded. A term is already what the schema wants and is passed through.
So `cast/2` has to work out which one it is looking at, and it does that by shape.

A `jsonb` column can only hand back an object with string keys, an array, a string, a number,
a boolean or null. Nothing else ever came from JSON. A struct, an atom key or an atom value
anywhere inside the value therefore rules out the document reading, and `cast/2` does not
attempt it:

```elixir
cast(%MyApp.Settings{theme: :dark}, params)   # term: a struct
cast(%{theme: :dark}, params)                 # term: atom keys
cast(%{"theme" => "dark"}, params)            # could be either
```

That distinction is load-bearing rather than tidy. Spectral fills fields a document leaves out
from the type's defaults, so decoding a term finds none of the keys it wants, succeeds anyway,
and hands back all defaults. Reading `%{theme: :dark}` as a document would quietly turn it
into `%{}`.

When the shape allows both, `cast/2` tries both. If only one succeeds, that is the answer. If
both succeed it takes the decoded one, because that is what `load/3` will return for the same
row and the two must agree. A type like `:dark | String.t()` needs this: `"dark"` is a valid
`String.t()` and is also what `:dark` encodes to, so keeping the string would mean the field
read back differently after a reload and reported a change on every save.

Nothing is re-encoded along the way, so a type that exposes only some of its struct's fields
still casts to the whole struct. `dump/3` drops the rest, which is where the type asked for
them to be dropped.

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

### Top-level values that are not objects

The type does not have to describe an object. `jsonb` holds any JSON value, so a type whose
top level is a list, or a bare string, number or boolean, needs no special handling:

```elixir
@type names :: [String.t()]          # stored as ["a", "b"]
@type tags :: [Tag.t()]              # stored as [{"name": ...}, ...]
@type mode :: :dark | String.t()     # stored as "dark"
```

This holds for non-scalar elements too: a list of structs is stored as an array of objects,
and `jsonb_typeof` reports `array` in every list case. `type/1` still reports `:map`, which is
only the name the Postgres adapter uses to pick a dumper. The parameterized callbacks produce
the value the driver encodes, and nothing between them checks that it is a map.

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
