defmodule EctoSpectral.Test.Profile do
  @moduledoc "Embedded schema, so embed_as/2 decides how the inner field is stored."
  use Ecto.Schema

  alias EctoSpectral.Test.Settings

  @primary_key false
  embedded_schema do
    field :nickname, :string
    field :settings, EctoSpectral.JSONB, module: Settings, type: :t
  end
end

defmodule EctoSpectral.Test.Account do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoSpectral.Test.Settings
  alias EctoSpectral.Test.Shapes
  alias EctoSpectral.Test.Tags

  schema "accounts" do
    field :settings, EctoSpectral.JSONB, module: Settings, type: :t
    field :required_settings, EctoSpectral.JSONB, module: Settings, type: :t
    field :shape, EctoSpectral.JSONB, module: Shapes, type: :shape
    field :names, EctoSpectral.JSONB, module: Tags, type: :names
    field :tags, EctoSpectral.JSONB, module: Tags, type: :tags

    field :lenient_settings, EctoSpectral.JSONB,
      module: Settings,
      type: :t,
      on_load_error: :error

    embeds_one :profile, EctoSpectral.Test.Profile, on_replace: :update
  end

  @fields ~w(settings required_settings shape names tags lenient_settings)a

  def changeset(account, params) do
    account
    |> cast(params, @fields)
    |> validate_required([:required_settings])
  end
end
