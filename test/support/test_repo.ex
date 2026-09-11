defmodule SpectralEcto.TestRepo do
  @moduledoc "Repo used by the test suite. Needs a real Postgres instance."

  use Ecto.Repo, otp_app: :spectral_ecto, adapter: Ecto.Adapters.Postgres
end
