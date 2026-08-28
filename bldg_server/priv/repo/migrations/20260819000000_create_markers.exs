defmodule BldgServer.Repo.Migrations.CreateMarkers do
  use Ecto.Migration

  def change do
    # A marker is a floor-level geometric idiom (like a road, but not anchored to
    # bldgs): a `path` polyline or a closed `area` polygon through floor cells.
    # Identity is (flr, name) so batteries can upsert idempotently.
    create table(:markers) do
      add :flr, :string
      add :name, :string
      add :marker_type, :string
      add :xs, {:array, :integer}
      add :ys, {:array, :integer}
      add :color, :string
      add :marker_class, :string, default: "road"
      add :owners, {:array, :string}
      add :data, :map

      timestamps()
    end

    create index(:markers, [:flr])
    create unique_index(:markers, [:flr, :name])
  end
end
