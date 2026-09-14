defmodule EctoSpectral.TestRepo.Migrations.AddDeclaredJsonbColumn do
  use Ecto.Migration

  @spec change() :: term()
  def change do
    alter table(:accounts) do
      add :declared_jsonb, :jsonb
    end
  end
end
