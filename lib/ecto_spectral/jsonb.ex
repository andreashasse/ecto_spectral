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
      A Spectral type reference, `{:type, name, arity}` or `{:record, name}`,
      also works, which is how you reach a type that takes parameters.
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

  `cast/2` takes both the native term and the external JSON document, and
  always answers with the term `load/3` would return for the same row:

      Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
      Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])

  Two details make that work.

  A struct is only ever read as a native term. A JSON document is never a
  struct, and a struct's keys are atoms, so reading one as a document would
  match nothing and fill every field from the struct's defaults, silently
  replacing the value the caller passed.

  Anything else that encodes successfully is a native term, and the value
  returned is that term encoded and decoded again. Some types accept the same
  value in both readings while meaning different things by it. `:dark |
  String.t()` is the clearest case: `"dark"` is a valid `String.t()` and also
  the encoding of `:dark`, so without this step `cast/2` would keep the
  string, `load/3` would answer `:dark`, and `equal?/3` would report a change
  on every save.

  `cast/2` is as strict as the type and no stricter. Spectral ignores document
  keys the type does not mention and fills fields the document omits from the
  struct's defaults, so a form that posts `settings[them]` instead of
  `settings[theme]` casts to the defaults rather than failing. Use
  `Ecto.Changeset` validations for anything the type does not express.

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

  `{:array, EctoSpectral.JSONB}` is not supported. It appears to work, but
  Ecto hands the whole list to the driver as a single `jsonb` parameter rather
  than as a `jsonb[]`. Use a type whose top level is a list instead.
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
    :defaults_to_struct,
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
    case encode(value, module, type) do
      {:ok, encoded} -> canonical(encoded, value, module, type)
      {:error, errors} when is_struct(value) -> cast_error(errors)
      {:error, _errors} -> cast_document(value, module, type)
      :not_a_term -> cast_document(value, module, type)
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

  defp cast_document(value, module, type) do
    case Spectral.decode(value, module, type, :json, [:pre_decoded]) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, errors} -> cast_error(errors)
    end
  end

  defp cast_error(errors),
    do: {:error, message: format_errors(errors), spectral_errors: errors}

  # Answer with the term load/3 would return, so a cast value and a loaded one
  # are never two representations of the same row. Falling back to the value
  # itself covers types Spectral encodes but cannot decode again; the value is
  # valid either way, since encoding it succeeded.
  defp canonical(encoded, value, module, type) do
    case Spectral.decode(encoded, module, type, :json, [:pre_decoded]) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _errors} -> {:ok, value}
    end
  end

  # Encoding a value that is nowhere near the type raises rather than returning
  # an error, and that raise is the only thing that means "not a term of this
  # type at all". A genuine configuration problem, such as a module compiled
  # without debug_info, raises from the decode attempt that follows instead.
  defp encode(value, module, type) do
    Spectral.encode(value, module, type, :json, [:pre_encoded])
  rescue
    _ in [FunctionClauseError, BadMapError] -> :not_a_term
  end

  defp load_error(_errors, _value, %{on_load_error: :error}), do: :error

  defp load_error(errors, value, %{module: module, type: type} = params) do
    raise LoadError,
      errors: errors,
      message: """
      cannot load #{inspect(value, printable_limit: 256, limit: 20)} \
      as #{inspect(module)}.#{type_name(type)}#{field_suffix(params)}

      #{format_errors(errors)}\
      """
  end

  defp field_suffix(%{field: nil}), do: ""
  defp field_suffix(%{schema: nil, field: field}), do: " for field #{inspect(field)}"

  defp field_suffix(%{schema: schema, field: field}),
    do: " for field #{inspect(field)} in #{inspect(schema)}"

  defp type_name(type) when is_atom(type), do: Atom.to_string(type)
  defp type_name(type), do: inspect(type)

  defp format_errors(errors), do: Enum.map_join(errors, "\n", &Exception.message/1)

  defp validate_options!(opts) do
    case Keyword.keys(opts) -- (@own_options ++ @ecto_options) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "EctoSpectral.JSONB got unknown option(s) #{inspect(unknown)}, " <>
                "expected one of #{inspect(@own_options)}"
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
