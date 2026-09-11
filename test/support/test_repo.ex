defmodule EctoSpectral.TestRepo do
  @moduledoc "Repo used by the test suite. Needs a real Postgres instance."

  use Ecto.Repo, otp_app: :ecto_spectral, adapter: Ecto.Adapters.Postgres
end
