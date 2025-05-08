defmodule BldgServerWeb.RoadController do
  use BldgServerWeb, :controller

  alias BldgServer.Relations
  alias BldgServer.Relations.Road

  action_fallback BldgServerWeb.FallbackController

  def index(conn, _params) do
    roads = Relations.list_roads()
    render(conn, "index.json", roads: roads)
  end

  def create(conn, %{"road" => road_params}) do
    with {:ok, %Road{} = road} <- Relations.create_road(road_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.road_path(conn, :show, road))
      |> render("show.json", road: road)
    end
  end

  def show(conn, %{"id" => id}) do
    road = Relations.get_road!(id)
    render(conn, "show.json", road: road)
  end

  def update(conn, %{"id" => id, "road" => road_params}) do
    road = Relations.get_road!(id)

    with {:ok, %Road{} = road} <- Relations.update_road(road, road_params) do
      render(conn, "show.json", road: road)
    end
  end

  def delete(conn, %{"id" => id}) do
    road = Relations.get_road!(id)

    with {:ok, %Road{}} <- Relations.delete_road(road) do
      send_resp(conn, :no_content, "")
    end
  end

  def look(conn, %{"flr" => flr}) do
    # unescape the flr parameter
    decoded_flr = URI.decode(flr)
    roads = Relations.list_roads_in_flr(decoded_flr)
    render(conn, "look.json", roads: roads)
  end

  def scan(conn, %{"flr" => flr}) do
    # unescape the flr parameter
    decoded_flr = URI.decode(flr)
    roads = Relations.list_all_roads_in_flr(decoded_flr)
    render(conn, "look.json", roads: roads)
  end

end
