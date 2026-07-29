defmodule BldgServerWeb.RoadController do
  use BldgServerWeb, :controller

  alias BldgServer.Relations
  alias BldgServer.Relations.Road
  alias BldgServerWeb.ResidentAuth

  action_fallback BldgServerWeb.FallbackController

  def index(conn, _params) do
    roads = Relations.list_roads()
    render(conn, "index.json", roads: roads)
  end

  # Roads are authorized against their floor's container bldg (roads have no
  # inherited-owner walk of their own). Owners are bound to the creator.
  def create(conn, %{"road" => road_params}) do
    road_params = bind_owners(conn, road_params)

    with :ok <- authorize_road_flr(conn, road_params),
         {:ok, %Road{} = road} <- Relations.create_road(road_params) do
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
    safe_params = Map.drop(road_params, ["owners"])

    with :ok <- ResidentAuth.authorize_container(conn, road.flr),
         {:ok, %Road{} = road} <- Relations.update_road(road, safe_params) do
      render(conn, "show.json", road: road)
    end
  end

  def delete(conn, %{"id" => id}) do
    road = Relations.get_road!(id)

    with :ok <- ResidentAuth.authorize_container(conn, road.flr),
         {:ok, %Road{}} <- Relations.delete_road(road) do
      send_resp(conn, :no_content, "")
    end
  end

  defp bind_owners(conn, params) do
    case conn.assigns[:current_resident] do
      %{email: email} -> Map.put(params, "owners", [email])
      _ -> params
    end
  end

  defp authorize_road_flr(conn, %{"flr" => flr}) when is_binary(flr) and flr != "",
    do: ResidentAuth.authorize_container(conn, flr)

  defp authorize_road_flr(_conn, _params), do: :ok

  @doc """
  Deletes every road in a floor subtree (the given flr and any nested floor).
  Used by the file-system-battery to clear stale roads before a re-render so
  layout-shifted roads don't orphan/accumulate. Body: %{"flr" => "<address>"}.
  """
  def delete_in_flr(conn, %{"flr" => flr}) do
    deleted =
      flr
      |> Relations.list_all_roads_in_flr()
      |> Enum.reduce(0, fn road, acc ->
        # Delete by struct; skip rows already removed (StaleEntryError).
        try do
          Relations.delete_road(road)
          acc + 1
        rescue
          Ecto.StaleEntryError -> acc
        end
      end)

    json(conn, %{deleted: deleted, flr: flr})
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
