defmodule BldgServerWeb.RoadView do
  use BldgServerWeb, :view
  alias BldgServerWeb.RoadView

  def render("index.json", %{roads: roads}) do
    %{data: render_many(roads, RoadView, "road.json")}
  end

  def render("show.json", %{road: road}) do
    %{data: render_one(road, RoadView, "road.json")}
  end

  def render("look.json", %{roads: roads}) do
    render_many(roads, RoadView, "road.json")
  end

  def render("road.json", %{road: road}) do
    %{id: road.id,
      flr: road.flr,
      from_address: road.from_address,
      to_address: road.to_address,
      from_x: road.from_x,
      from_y: road.from_y,
      to_x: road.to_x,
      to_y: road.to_y,
      owners: road.owners,
      color: road.color,
      road_class: road.road_class
    }
  end
end
