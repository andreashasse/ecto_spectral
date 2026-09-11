import Config

if config_env() == :test do
  config :ecto_spectral, ecto_repos: [EctoSpectral.TestRepo]

  config :ecto_spectral, EctoSpectral.TestRepo,
    username: System.get_env("PGUSER", "postgres"),
    password: System.get_env("PGPASSWORD", "postgres"),
    hostname: System.get_env("PGHOST", "localhost"),
    port: String.to_integer(System.get_env("PGPORT", "5432")),
    database: System.get_env("PGDATABASE", "ecto_spectral_test"),
    pool: Ecto.Adapters.SQL.Sandbox,
    priv: "priv/repo",
    log: false

  # Postgrex needs a JSON library to encode jsonb parameters. Elixir 1.18's
  # built-in JSON module has the encode_to_iodata!/1 and decode!/1 it expects.
  config :postgrex, :json_library, JSON

  config :logger, level: :warning
end
