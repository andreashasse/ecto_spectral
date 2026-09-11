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
