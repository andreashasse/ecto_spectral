defmodule EctoSpectral.TestRepo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :settings, :map
      add :required_settings, :map, null: false
      add :shape, :map
      add :names, :map
      add :tags, :map
      add :lenient_settings, :map
      add :profile, :map
      add :mode, :map
      add :number, :map
    end
  end
end
