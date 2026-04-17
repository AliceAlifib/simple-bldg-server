defmodule BldgServer.Repo.Migrations.AddFavoriteViewPointsToBldgs do
  use Ecto.Migration

  def change do
    alter table(:bldgs) do
      add :favorite_view_points, {:array, :map}, default: []
    end
  end
end
