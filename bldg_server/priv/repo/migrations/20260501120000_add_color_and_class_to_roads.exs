defmodule BldgServer.Repo.Migrations.AddColorAndClassToRoads do
  use Ecto.Migration

  def change do
    alter table(:roads) do
      # Optional named color (matches the metric-color palette in the
      # bldg-client). NULL = render with the road prefab's default material.
      add :color, :string

      # Roads-domain class enum: highway | road | lane | path. Drives both
      # the road's perpendicular width and its y-elevation in the renderer
      # (lower-class roads sit above higher-class ones to overlay cleanly).
      # Default "road" so existing rows render exactly as before.
      add :road_class, :string, default: "road", null: false
    end
  end
end
