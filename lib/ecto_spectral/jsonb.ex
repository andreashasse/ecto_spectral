defmodule EctoSpectral.JSONB do
  @moduledoc """
  An `Ecto.ParameterizedType` that stores a Spectral-typed value in a `jsonb` column.

      defmodule MyApp.Repo.Migrations.CreateAccounts do
        use Ecto.Migration

        def change do
          create table(:accounts) do
            add :settings, :map
          end
        end
      end

      defmodule MyApp.Account do
        use Ecto.Schema

        schema "accounts" do
          field :settings, EctoSpectral.JSONB, module: MyApp.Settings, type: :t
        end
      end

  The migration names the database type, not `EctoSpectral.JSONB`: `:map`,
  which Postgres renders as `jsonb`, or `:jsonb` directly.

  ## Which callback goes which way

  A `jsonb` column never hands Elixir a JSON string. The driver does its own
  serialization, so the callbacks meet it already parsed:

    * `dump/3` runs on the way to the column and **encodes**: it turns a term
      of the type into the map, list or scalar the driver will serialize.
    * `load/3` runs on the way back and **decodes**: it turns the document the
      driver parsed back into a term of the type.
    * `cast/2` runs on the way in from outside, a controller or a form, and
      also **decodes**. It is not the encoding step, even though its result
      is bound for the column; `dump/3` is, and it runs later.

  Those are Spectral's `:pre_encoded` and `:pre_decoded` options exactly.

  ## Options

    * `:module` - required. The module holding the type definition.
    * `:type` - required. The name of the type in that module, as an atom.
      A Spectral type reference also works: `{:type, name, arity}` picks
      between types that share a name, and `{:record, name}` names a record.
      A type that takes a parameter needs a concrete alias; see below.
    * `:on_load_error` - `:raise` (default) or `:error`. See "Errors" below.

  Any other option is rejected, apart from the ones `Ecto.Schema` itself adds
  to a field.

  ## `nil`

  A `NULL` column loads as `nil`, and `nil` is written as `NULL`. `NOT NULL` is
  enforced by the database and by `Ecto.Changeset.validate_required/3`, not
  by the type.

  A `jsonb` document that is itself `null` also loads as `nil`, without being
  checked against the type, and the next write replaces it with a real `NULL`.

  ## Casting

  `cast/2` takes both the typed value your own code builds and the
  string-keyed document a controller or a form sends:

      Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])
      Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])

  A value containing a struct, an atom key or an atom value is taken as the
  typed value and kept as it is. Anything else is decoded as a document.

    * A misspelled key is not an error. Spectral ignores keys the type does not
      mention and fills missing fields from the struct defaults, so
      `%{"them" => "dark"}` casts to the defaults, and a stored document with
      nothing in common with the type loads as the defaults. Validate anything
      the type does not express with `Ecto.Changeset`.
    * A type using Spectral's `only` still casts to the whole struct. The
      excluded fields are dropped on write.
    * A value valid both ways reads as it will after a reload: with
      `:dark | String.t()`, casting `"dark"` gives `:dark`.

  ## Errors

    * `cast/2` returns `{:error, message: ..., spectral_errors: ...}`, so
      changeset validation keeps Spectral's detail.
    * `dump/3` can only return `:error`. Ecto turns that into an
      `Ecto.ChangeError` naming the field and value.
    * `load/3` raises `EctoSpectral.LoadError` with Spectral's error list,
      because data already in the column that does not match its type is a
      bug rather than user input. Pass `on_load_error: :error` to get Ecto's
      own `ArgumentError` instead, which names the field but not the reason.

  Postgres normalises `jsonb` numbers through `numeric`, which drops exponent
  notation, so a `float()` of `1.0e10` comes back as the integer `10000000000`
  and no longer matches `float()`. A column holding large-magnitude floats can
  fail to load data this type itself wrote. `on_load_error: :error` only
  changes which exception you get.

  ## Top-level values that are not objects

  The type does not have to describe an object. `jsonb` holds any JSON value:

      @type names :: [String.t()]          # stored as ["a", "b"]
      @type tags :: [Tag.t()]              # stored as [{"name": ...}, ...]
      @type mode :: :dark | String.t()     # stored as "dark"

  ## Types that take a parameter

  A type with a parameter cannot be named as the field type, because nothing
  can supply the argument, and it raises on first use. Define a concrete alias
  and name that instead:

      @type box(value) :: %{value: value}
      @type int_box :: box(integer())

      field :count, EctoSpectral.JSONB, module: MyApp.Types, type: :int_box

  ## Scope

  Tested against Postgres only.

  `{:array, EctoSpectral.JSONB}` works against a column declared
  `add :col, {:array, :map}`, stored as a `jsonb[]` with one document per
  element. Against a plain `jsonb` column the list is stored as a single JSON
  array instead, which round trips but is not what the field says it is.
  """

  use Ecto.ParameterizedType

  alias EctoSpectral.LoadError

  @own_options [:module, :type, :on_load_error]

  # Ecto merges the field's own options into what it hands init/1, so those
  # have to be tolerated too. Mirrors Ecto.Schema's @field_opts, plus the two
  # keys Ecto injects.
  @ecto_options [
    :autogenerate,
    :default,
    :defaults,
    :define_field,
    :field,
    :foreign_key,
    :load_in_query,
    :on_replace,
    :on_writable_violation,
    :primary_key,
    :read_after_writes,
    :redact,
    :references,
    :schema,
    :skip_default_validation,
    :source,
    :virtual,
    :where,
    :writable
  ]

  @type params :: %{
          module: module(),
          type: atom() | Spectral.sp_type_reference(),
          on_load_error: :raise | :error,
          field: atom() | nil,
          schema: module() | nil
        }

  @impl Ecto.ParameterizedType
  def init(opts) do
    validate_options!(opts)

    %{
      module: fetch_required!(opts, :module),
      type: fetch_required!(opts, :type),
      on_load_error: on_load_error(opts),
      field: Keyword.get(opts, :field),
      schema: Keyword.get(opts, :schema)
    }
  end

  # `:map` only tells the adapter which dumper to use. The callbacks produce the
  # value the driver encodes and nothing checks that it is a map, so a type
  # whose top level is a list or a scalar needs no separate field type.
  @impl Ecto.ParameterizedType
  def type(_params), do: :map

  # Ecto.Type dispatches to parameterized types before its own nil shortcut, so
  # nil reaches cast/2, dump/3 and load/3 alike, a NULL column included. Plain
  # Ecto.Type modules never see nil, which makes these clauses easy to miss.
  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  # JSON can only produce objects with string keys, arrays, strings, numbers,
  # booleans and null. A value with a struct, an atom key or an atom value
  # anywhere inside it is therefore a term of the type and is never read as a
  # document. That matters because Spectral fills fields a document omits from
  # the type's defaults: decoding a term would succeed and return all defaults.
  # Nothing is re-encoded here, so a type using `only` keeps its excluded fields
  # until dump/3 drops them.
  def cast(value, %{module: module, type: type}) do
    cast_by_shape(document_shaped?(value), value, module, type)
  end

  @impl Ecto.ParameterizedType
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, %{module: module, type: type}) do
    case Spectral.encode(value, module, type, :json, [:pre_encoded]) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, _errors} -> :error
    end
  end

  @impl Ecto.ParameterizedType
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, %{module: module, type: type} = params) do
    case Spectral.decode(value, module, type, :json, [:pre_decoded]) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, errors} -> load_error(errors, value, params)
    end
  end

  @doc """
  Compares two values of the field.

  Uses `===/2` rather than `==/2`, so that an integer and the same value as a
  float count as a change. `Ecto.Changeset` drops a change whose new value is
  `equal?/3` to the old one, and `1` and `1.0` are different documents once
  they reach the column.
  """
  @impl Ecto.ParameterizedType
  def equal?(left, right, _params), do: left === right

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump

  @impl Ecto.ParameterizedType
  def format(%{module: module, type: type}) do
    "#EctoSpectral.JSONB<#{inspect(module)}.#{type_name(type)}>"
  end

  defp cast_by_shape(true, value, module, type), do: cast_either(value, module, type)
  defp cast_by_shape(false, value, module, type), do: cast_native(value, module, type)

  # The value cannot have come out of a JSON column, so the document reading is
  # not tried at all. Trying it is what used to replace a value the caller
  # passed with the type's defaults, since a document reading matches none of
  # the atom keys and fills every field it did not find.
  defp cast_native(value, module, type) do
    case encode(value, module, type) do
      {:ok, _encoded} -> {:ok, value}
      {:error, errors} -> cast_error(errors)
      {:raised, exception} -> {:error, message: Exception.message(exception)}
    end
  end

  # The value is shaped like a document, so it could be either reading. When
  # both claim it, answer with the one `load/3` would give, so that a cast
  # value and a loaded one are never two representations of the same row. With
  # `:dark | String.t()`, "dark" is a valid String.t() and also what :dark
  # encodes to; keeping the string would make every save look like a change.
  defp cast_either(value, module, type) do
    encoded = encode(value, module, type)
    decoded = Spectral.decode(value, module, type, :json, [:pre_decoded])

    case {encoded, decoded} do
      {{:ok, _encoded}, {:ok, term}} -> {:ok, term}
      {{:ok, _encoded}, {:error, _errors}} -> {:ok, value}
      {_encoded, {:ok, term}} -> {:ok, term}
      {_encoded, {:error, errors}} -> cast_error(errors)
    end
  end

  defp cast_error(errors),
    do: {:error, message: format_errors(errors), spectral_errors: errors}

  # Everything a JSON column can hand back: objects with string keys, arrays,
  # strings, numbers, booleans and null. Anything else, a struct or an atom key
  # or an atom value, can only be a term of the type.
  defp document_shaped?(value) when is_binary(value) or is_number(value), do: true
  defp document_shaped?(value) when is_boolean(value) or is_nil(value), do: true
  defp document_shaped?(%_struct{}), do: false

  defp document_shaped?(value) when is_map(value),
    do: Enum.all?(value, fn {key, item} -> is_binary(key) and document_shaped?(item) end)

  defp document_shaped?(value) when is_list(value), do: Enum.all?(value, &document_shaped?/1)
  defp document_shaped?(_value), do: false

  # For a value far enough from the type, older releases raise instead of
  # returning errors: Spectral 0.13 a FunctionClauseError from its own error
  # handling, and spectra 0.14.0 a BadMapError. From spectra 0.14.1 it is an
  # error return. Callers treat a raise and an error return alike, so every
  # accepted release works. A configuration problem, such as a module compiled
  # without debug_info, raises an ErlangError and is deliberately left to
  # propagate.
  defp encode(value, module, type) do
    Spectral.encode(value, module, type, :json, [:pre_encoded])
  rescue
    exception in [FunctionClauseError, BadMapError] -> {:raised, exception}
  end

  defp load_error(_errors, _value, %{on_load_error: :error}), do: :error

  defp load_error(errors, value, %{module: module, type: type} = params) do
    raise LoadError,
      errors: errors,
      message: """
      cannot load #{describe(value)} as #{inspect(module)}.#{type_name(type)}#{field_suffix(params)}

      #{format_errors(errors)}\
      """
  end

  defp field_suffix(%{field: nil}), do: ""
  defp field_suffix(%{schema: nil, field: field}), do: " for field #{inspect(field)}"

  defp field_suffix(%{schema: schema, field: field}),
    do: " for field #{inspect(field)} in #{inspect(schema)}"

  # `:limit` bounds how wide a document is printed but not how deep, and jsonb
  # nests as far as it likes, so the rendered string is cut to a fixed size.
  defp describe(value) do
    case inspect(value, printable_limit: 256, limit: 20) do
      <<head::binary-size(512), _rest::binary>> -> head <> "..."
      whole -> whole
    end
  end

  defp type_name(type) when is_atom(type), do: Atom.to_string(type)
  defp type_name(type), do: inspect(type)

  defp format_errors(errors), do: Enum.map_join(errors, "\n", &Exception.message/1)

  defp validate_options!(opts) do
    case Keyword.keys(opts) -- (@own_options ++ @ecto_options) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "EctoSpectral.JSONB got unknown option(s) #{inspect(unknown)}, expected one of " <>
                "#{inspect(@own_options)} or an option Ecto.Schema accepts on a field"
    end
  end

  defp fetch_required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "EctoSpectral.JSONB requires the #{inspect(key)} option, got: #{inspect(opts)}"
    end
  end

  defp on_load_error(opts) do
    case Keyword.get(opts, :on_load_error, :raise) do
      value when value in [:raise, :error] ->
        value

      other ->
        raise ArgumentError,
              "EctoSpectral.JSONB :on_load_error must be :raise or :error, got: #{inspect(other)}"
    end
  end
end
