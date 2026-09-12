defmodule EctoSpectral.Test.Settings do
  @moduledoc "A plain struct type, the common case for a jsonb column."
  use Spectral

  defstruct theme: :light, notifications: true, locale: nil

  @type t :: %__MODULE__{
          theme: :light | :dark,
          notifications: boolean(),
          locale: String.t() | nil
        }
end

defmodule EctoSpectral.Test.Shapes do
  @moduledoc "A self-describing union: the discriminator lives in the document."
  use Spectral

  defmodule Circle do
    @moduledoc false
    use Spectral
    defstruct kind: :circle, radius: nil
    @type t :: %Circle{kind: :circle, radius: float()}
  end

  defmodule Square do
    @moduledoc false
    use Spectral
    defstruct kind: :square, side: nil
    @type t :: %Square{kind: :square, side: float()}
  end

  @type shape :: Circle.t() | Square.t()
end

defmodule EctoSpectral.Test.Tags do
  @moduledoc "A type whose top level is a list rather than a map."
  use Spectral

  defmodule Tag do
    @moduledoc false
    use Spectral
    defstruct [:name, :weight]
    @type t :: %Tag{name: String.t(), weight: non_neg_integer()}
  end

  @type names :: [String.t()]
  @type tags :: [Tag.t()]
end

defmodule EctoSpectral.Test.Modes do
  @moduledoc """
  A union whose two branches accept the same JSON document.

  `"dark"` is a valid `String.t()` and also the encoding of `:dark`, so the
  native and document readings of it disagree.
  """
  use Spectral

  @type mode :: :dark | String.t()
end

defmodule EctoSpectral.Test.Numbers do
  @moduledoc "Floats, which Postgres normalises through `numeric` in a jsonb column."
  use Spectral

  defstruct [:value]

  @type t :: %__MODULE__{value: float()}
end

defmodule EctoSpectral.Test.Prefs do
  @moduledoc "A plain map type with atom keys, so the native form is not document-shaped."
  use Spectral

  @type t :: %{optional(:theme) => :light | :dark, optional(:rows) => non_neg_integer()}
end

defmodule EctoSpectral.Test.Partial do
  @moduledoc "A type that exposes only some of its struct's fields."
  use Spectral

  defstruct [:name, :age, :secret]

  spectral(only: [:name])

  @type t :: %__MODULE__{
          name: String.t(),
          age: non_neg_integer() | nil,
          secret: String.t() | nil
        }
end
