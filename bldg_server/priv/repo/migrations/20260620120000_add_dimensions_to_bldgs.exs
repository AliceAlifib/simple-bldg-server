defmodule BldgServer.Repo.Migrations.AddDimensionsToBldgs do
  use Ecto.Migration

  def change do
    alter table(:bldgs) do
      # Footprint on the bldg's floor, in grid cells, with the bldg's {x, y} as
      # the bottom-left origin. Default 1x1 keeps every existing bldg a single
      # cell (the historical point model), so legacy data and placement are
      # unchanged.
      add :width, :integer, default: 1, null: false
      add :height, :integer, default: 1, null: false
    end
  end
end
