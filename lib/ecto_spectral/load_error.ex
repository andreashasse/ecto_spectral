defmodule EctoSpectral.LoadError do
  @moduledoc """
  Raised when a stored `jsonb` document does not match the declared Spectral type.

  `c:Ecto.ParameterizedType.load/3` can only answer `:error`, which loses the
  reason entirely. A load failure means the column already holds data that does
  not match the type, which is a data bug rather than user input, so
  `EctoSpectral.JSONB` raises this instead. Pass `on_load_error: :error` to the
  field to get Ecto's own `ArgumentError` back.

  The `:errors` field carries the `Spectral.Error` structs that caused it.
  """

  defexception [:message, :errors]
end
