defmodule EctoSpectral.TestRepo.Migrations.AddAmbiguousAndArrayColumns do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :mode, :map
      add :number, :map
      add :many_settings, {:array, :map}
      add :prefs, :map
      add :partial, :map
    end
  end
end
