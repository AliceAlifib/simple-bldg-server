defmodule BldgServer.Repo.Migrations.AddCurveToRoads do
  use Ecto.Migration

  def change do
    alter table(:roads) do
      # "auto" (default): the client's planner may bend the road around
      # obstacles/overlaps; "never": always render straight (e.g. metric lanes
      # overlaying the fishbone spine).
      add :curve, :string, default: "auto"
    end
  end
end
