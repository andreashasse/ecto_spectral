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
    * `:on_load_error` - `:raise` (default) or `:error`. See "Errors" below.

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

  ## `nil`

  `Ecto.Type` dispatches to parameterized types *before* its own `nil`
  shortcut, so a `NULL` column arrives as `nil` in `cast/2`, `load/3` and
  `dump/3` alike. All three pass it straight through; a `NOT NULL` column is
  enforced by the database and by `Ecto.Changeset.validate_required/3`, not
  here.

  ## What `cast/2` accepts

  `cast/2` first checks whether the value is already a valid term of the type,
  and passes it through unchanged when it is. Only if that fails does it decode
  the value as an external JSON document, which is the string-keyed shape a
  controller or a form hands you. That means both of these work:

      Ecto.Changeset.cast(account, %{"settings" => %{"theme" => "dark"}}, [:settings])
      Ecto.Changeset.cast(account, %{settings: %MyApp.Settings{theme: :dark}}, [:settings])

  The order matters. A struct is a map with atom keys, and Spectral fills
  fields it does not find in a document from the struct's defaults, so
  decoding a struct succeeds and quietly returns the defaults. Validating it
  as a native term first is what keeps that from happening. When neither
  reading succeeds, the error reported is the decoding one.

  ## Lists at the top level

  A type whose top level is a list dumps to a list, which Postgres stores in a
  `jsonb` column without complaint. Ecto's `:map` is only the name of the
  adapter's dumper here; the parameterized callbacks bypass its map check, so
  no separate field type is needed.
  """

  use Ecto.ParameterizedType

  alias EctoSpectral.LoadError

  @type params :: %{
          module: module(),
          type: atom(),
          on_load_error: :raise | :error,
          field: atom() | nil,
          schema: module() | nil
        }

  @impl Ecto.ParameterizedType
  def init(opts) do
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
    if native?(value, module, type) do
      {:ok, value}
    else
      case Spectral.decode(value, module, type, :json, [:pre_decoded]) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, errors} -> {:error, message: format_errors(errors), spectral_errors: errors}
      end
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

  @impl Ecto.ParameterizedType
  def equal?(left, right, _params), do: left == right

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump

  @impl Ecto.ParameterizedType
  def format(%{module: module, type: type}) do
    "#EctoSpectral.JSONB<#{inspect(module)}.#{type}>"
  end

  # Encoding a value that is nowhere near the type can raise rather than return
  # an error, so a failure here only means "not a native term of this type".
  # A genuine configuration problem, such as a module compiled without
  # debug_info, raises from the decode attempt that follows instead.
  defp native?(value, module, type) do
    match?({:ok, _}, Spectral.encode(value, module, type, :json, [:pre_encoded]))
  rescue
    _ -> false
  end

  defp load_error(_errors, _value, %{on_load_error: :error}), do: :error

  defp load_error(errors, value, %{module: module, type: type} = params) do
    raise LoadError,
      errors: errors,
      message: """
      cannot load #{inspect(value)} as #{inspect(module)}.#{type}#{field_suffix(params)}

      #{format_errors(errors)}\
      """
  end

  defp field_suffix(%{field: nil}), do: ""
  defp field_suffix(%{schema: nil, field: field}), do: " for field #{inspect(field)}"

  defp field_suffix(%{schema: schema, field: field}),
    do: " for field #{inspect(field)} in #{inspect(schema)}"

  defp format_errors(errors), do: Enum.map_join(errors, "\n", &Exception.message/1)

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
