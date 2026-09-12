defmodule EctoSpectral.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/andreashasse/ecto_spectral"

  def project do
    [
      app: :ecto_spectral,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      name: "EctoSpectral",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix], plt_local_path: "priv/plts"]
    ]
  end

  def application do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:spectral, "~> 0.13.0"},
      {:ecto, "~> 3.12"},
      # Only the tests talk to a database.
      {:ecto_sql, "~> 3.12", only: [:dev, :test]},
      {:postgrex, "~> 0.19", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp description do
    """
    An Ecto.ParameterizedType that stores Spectral-typed values in jsonb columns.
    """
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url, "Spectral" => "https://hexdocs.pm/spectral"},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end
