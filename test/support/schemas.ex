defmodule SpectralEcto.Test.Profile do
  @moduledoc "Embedded schema, so embed_as/2 decides how the inner field is stored."
  use Ecto.Schema

  alias SpectralEcto.Test.Settings

  @primary_key false
  embedded_schema do
    field :nickname, :string
    field :settings, SpectralEcto.JSONB, module: Settings, type: :t
  end
end

defmodule SpectralEcto.Test.Account do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias SpectralEcto.Test.Settings
  alias SpectralEcto.Test.Shapes
  alias SpectralEcto.Test.Tags

  schema "accounts" do
    field :settings, SpectralEcto.JSONB, module: Settings, type: :t
    field :required_settings, SpectralEcto.JSONB, module: Settings, type: :t
    field :shape, SpectralEcto.JSONB, module: Shapes, type: :shape
    field :names, SpectralEcto.JSONB, module: Tags, type: :names
    field :tags, SpectralEcto.JSONB, module: Tags, type: :tags

    field :lenient_settings, SpectralEcto.JSONB,
      module: Settings,
      type: :t,
      on_load_error: :error

    embeds_one :profile, SpectralEcto.Test.Profile, on_replace: :update
  end

  @fields ~w(settings required_settings shape names tags lenient_settings)a

  def changeset(account, params) do
    account
    |> cast(params, @fields)
    |> validate_required([:required_settings])
  end
end
