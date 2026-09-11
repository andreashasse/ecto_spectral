alias Ecto.Adapters.SQL.Sandbox

case SpectralEcto.TestRepo.start_link() do
  {:ok, _pid} ->
    :ok

  {:error, reason} ->
    IO.puts(:stderr, """
    Could not connect to Postgres: #{inspect(reason)}

    The suite needs a real Postgres instance, because the point of it is to
    write and read actual jsonb. Start one with:

        docker compose up -d

    and override PGHOST/PGPORT/PGUSER/PGPASSWORD if yours lives elsewhere.
    """)

    System.halt(1)
end

Sandbox.mode(SpectralEcto.TestRepo, :manual)
ExUnit.start()
