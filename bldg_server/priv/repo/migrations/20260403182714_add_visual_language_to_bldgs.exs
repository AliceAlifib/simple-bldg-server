defmodule BldgServer.Repo.Migrations.AddVisualLanguageToBldgs do
  use Ecto.Migration

  def change do
    alter table(:bldgs) do
      add :visual_language, :map
    end
  end
end
