defmodule BldgServerWeb.MarkerView do
  use BldgServerWeb, :view
  alias BldgServerWeb.MarkerView

  def render("index.json", %{markers: markers}) do
    %{data: render_many(markers, MarkerView, "marker.json")}
  end

  def render("show.json", %{marker: marker}) do
    %{data: render_one(marker, MarkerView, "marker.json")}
  end

  def render("look.json", %{markers: markers}) do
    render_many(markers, MarkerView, "marker.json")
  end

  def render("marker.json", %{marker: marker}) do
    %{
      id: marker.id,
      flr: marker.flr,
      name: marker.name,
      marker_type: marker.marker_type,
      xs: marker.xs,
      ys: marker.ys,
      color: marker.color,
      marker_class: marker.marker_class,
      owners: marker.owners,
      data: marker.data
    }
  end
end
