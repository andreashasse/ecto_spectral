defmodule EctoSpectral.JSONB do
  @moduledoc """
  An `Ecto.ParameterizedType` that stores a Spectral-typed value in a `jsonb` column.

      defmodule MyApp.Account do
        use Ecto.Schema

        schema "accounts" do
          field :settings, EctoSpectral.JSONB, module: MyApp.Settings, type: :t
        end
      end

  The column is declared `:map` in the migration, which Postgres renders as
  `jsonb`. A `jsonb` column never hands Elixir a JSON string: the driver does
  its own serialization, so `load/3` receives an already-decoded map and
  `dump/3` is expected to return a map the driver will encode. That is exactly
  what Spectral's `:pre_decoded` and `:pre_encoded` options produce.

  ## Options

    * `:module` - required. The module holding the type definition.
    * `:type` - required. The name of the type in that module, as an atom.
      A Spectral type reference also works: `{:type, name, arity}` picks
      between types that share a name, and `{:record, name}` names a record.
      Neither supplies a type parameter; a type that takes one cannot be used
      as a field.
    * `:on_load_error` - `:raise` (default) or `:error`. See "Errors" below.

  Any other option is rejected, apart from the ones `Ecto.Schema` itself adds
  to a field.

  ## `nil`

  `Ecto.Type` dispatches to parameterized types *before* its own `nil`
  shortcut, so a `NULL` column arrives as `nil` in `cast/2`, `load/3` and
  `dump/3` alike. All three pass it straight through; a `NOT NULL` column is
  enforced by the database and by `Ecto.Changeset.validate_required/3`, not
  here.

  A `jsonb` document that is itself `null` is not distinguishable from a SQL
  `NULL` by the time the value reaches `load/3`: the driver decodes both to
  `nil`. Such a row therefore loads as `nil` without being checked against the
  type, and the next write replaces it with a real `NULL`.

  ## What `cast/2` accepts

  `cast/2` takes both the native term and the external JSON document:

      Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
      Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])

  Which reading it uses comes down to shape. A `jsonb` column can only hand
  back an object with string keys, an array, a string, a number, a boolean or
  null, so a value carrying a struct, an atom key or an atom value anywhere
  inside it can only be a term of the type, and the document reading is not
  tried at all. That matters because reading such a value as a document
  matches none of its keys and fills every field from the type's defaults,
  which would silently replace what the caller passed.

  When the value could be either, and both readings claim it, the answer is
  the one `load/3` would give. Some types accept the same value both ways
  while meaning different things by it: with `:dark | String.t()`, `"dark"` is
  a valid `String.t()` and also the encoding of `:dark`. Otherwise `cast/2`
  would keep the string, `load/3` would answer `:dark`, and `equal?/3` would
  report a change on every save.

  Nothing is re-encoded on the way through, so a type that exposes only some
  of its struct's fields still casts to the whole struct. The fields it does
  not expose are dropped by `dump/3`, where the type says they should be.

  ## Leniency

  Neither `cast/2` nor `load/3` is stricter than the type. Spectral ignores
  document keys the type does not mention and fills fields the document omits
  from the struct's defaults, so a form that posts `settings[them]` instead of
  `settings[theme]` casts to the defaults rather than failing, and a stored
  document with no keys in common with the type loads as the defaults rather
  than raising. What `load/3` catches is a key that is present and wrong, not
  a document that is simply unrelated. Use `Ecto.Changeset` validations for
  anything the type does not express.

  ## Errors

  The three callbacks differ in how much they can say:

    * `cast/2` returns `{:error, message: ..., spectral_errors: ...}`, so
      changeset validation keeps the detail. The message is Spectral's own
      error text.
    * `dump/3` can only return `:error`. Ecto turns that into an
      `Ecto.ChangeError` naming the field and value, without Spectral's error
      list.
    * `load/3` can only return `:error` too, which Ecto turns into an
      `ArgumentError` naming the field and the schema. Because a load failure
      means the column already holds data that does not match the type, which
      is a bug rather than user input, this type raises
      `EctoSpectral.LoadError` with the full error list instead. Pass
      `on_load_error: :error` to get Ecto's `ArgumentError` back.

  One case is worth knowing before choosing `:raise`. Postgres normalises
  `jsonb` numbers through `numeric`, which drops exponent notation, so a
  `float()` of `1.0e10` comes back as the integer `10000000000` and no longer
  matches `float()`. A column holding large-magnitude floats can therefore
  fail to load data this type itself wrote. `on_load_error: :error` does not
  make that legal, it only changes which exception you get.

  ## Lists at the top level

  A type whose top level is a list dumps to a list, which Postgres stores in a
  `jsonb` column without complaint. Ecto's `:map` is only the name of the
  adapter's dumper here; the parameterized callbacks bypass its map check, so
  no separate field type is needed.

  ## Scope

  Tested against Postgres, where `:map` means `jsonb` and the adapter passes
  the dumped value to the driver untouched. Other adapters make their own
  arrangements for `:map` and are neither tested nor supported.

  `{:array, EctoSpectral.JSONB}` works, against a column declared
  `add :col, {:array, :map}`. Ecto dumps the elements one at a time and
  Postgres stores them as a real `jsonb[]`. Point it at a plain `jsonb` column
  by mistake and the list is stored as a single JSON array instead, which
  round trips but is not what the field says it is.
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

  @impl Ecto.ParameterizedType
  def type(_params), do: :map

  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, %{module: module, type: type}) do
    if document_shaped?(value) do
      cast_either(value, module, type)
    else
      cast_native(value, module, type)
    end
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
  # value and a loaded one are never two representations of the same row.
  defp cast_either(value, module, type) do
    encoded = encode(value, module, type)
    decoded = Spectral.decode(value, module, type, :json, [:pre_decoded])

    case {encoded, decoded} do
      {{:ok, _}, {:ok, term}} -> {:ok, term}
      {{:ok, _}, {:error, _}} -> {:ok, value}
      {_, {:ok, term}} -> {:ok, term}
      {_, {:error, errors}} -> cast_error(errors)
    end
  end

  defp cast_error(errors),
    do: {:error, message: format_errors(errors), spectral_errors: errors}

  # Everything a JSON column can hand back: objects with string keys, arrays,
  # strings, numbers, booleans and null. Anything else, a struct or an atom key
  # or an atom value, can only be a term of the type.
  defp document_shaped?(value) when is_binary(value) or is_number(value), do: true
  defp document_shaped?(value) when is_boolean(value) or is_nil(value), do: true
  defp document_shaped?(%_{}), do: false

  defp document_shaped?(value) when is_map(value),
    do: Enum.all?(value, fn {key, item} -> is_binary(key) and document_shaped?(item) end)

  defp document_shaped?(value) when is_list(value), do: Enum.all?(value, &document_shaped?/1)
  defp document_shaped?(_value), do: false

  # Spectral raises rather than returning an error for a value far enough from
  # the type, so both outcomes have to be handled. A configuration problem,
  # such as a module compiled without debug_info, raises an ErlangError and is
  # deliberately left to propagate.
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
