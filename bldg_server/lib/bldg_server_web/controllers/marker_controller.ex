defmodule BldgServerWeb.MarkerController do
  use BldgServerWeb, :controller

  alias BldgServer.Relations
  alias BldgServer.Relations.Marker
  alias BldgServerWeb.ResidentAuth

  action_fallback BldgServerWeb.FallbackController

  def index(conn, _params) do
    markers = Relations.list_markers()
    render(conn, "index.json", markers: markers)
  end

  # Markers are authorized against their floor's container bldg (markers have
  # no inherited-owner walk of their own). Owners are bound to the creator.
  def create(conn, %{"marker" => marker_params}) do
    marker_params = bind_owners(conn, marker_params)

    with :ok <- authorize_marker_flr(conn, marker_params),
         {:ok, %Marker{} = marker} <- Relations.create_marker(marker_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.marker_path(conn, :show, marker))
      |> render("show.json", marker: marker)
    end
  end

  def show(conn, %{"id" => id}) do
    marker = Relations.get_marker!(id)
    render(conn, "show.json", marker: marker)
  end

  def update(conn, %{"id" => id, "marker" => marker_params}) do
    marker = Relations.get_marker!(id)
    safe_params = Map.drop(marker_params, ["owners"])

    with :ok <- ResidentAuth.authorize_container(conn, marker.flr),
         {:ok, %Marker{} = marker} <- Relations.update_marker(marker, safe_params) do
      render(conn, "show.json", marker: marker)
    end
  end

  def delete(conn, %{"id" => id}) do
    marker = Relations.get_marker!(id)

    with :ok <- ResidentAuth.authorize_container(conn, marker.flr),
         {:ok, %Marker{}} <- Relations.delete_marker(marker) do
      send_resp(conn, :no_content, "")
    end
  end

  defp bind_owners(conn, params) do
    case conn.assigns[:current_resident] do
      %{email: email} -> Map.put(params, "owners", [email])
      _ -> params
    end
  end

  defp authorize_marker_flr(conn, %{"flr" => flr}) when is_binary(flr) and flr != "",
    do: ResidentAuth.authorize_container(conn, flr)

  defp authorize_marker_flr(_conn, _params), do: :ok

  @doc """
  Deletes every marker in a floor subtree (the given flr and any nested floor).
  Used by batteries to clear stale markers before a re-render. Body:
  %{"flr" => "<address>"}.
  """
  def delete_in_flr(conn, %{"flr" => flr}) do
    deleted =
      flr
      |> Relations.list_all_markers_in_flr()
      |> Enum.reduce(0, fn marker, acc ->
        # Delete by struct; skip rows already removed (StaleEntryError).
        try do
          Relations.delete_marker(marker)
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
    markers = Relations.list_markers_in_flr(decoded_flr)
    render(conn, "look.json", markers: markers)
  end

  def scan(conn, %{"flr" => flr}) do
    # unescape the flr parameter
    decoded_flr = URI.decode(flr)
    markers = Relations.list_all_markers_in_flr(decoded_flr)
    render(conn, "look.json", markers: markers)
  end
end
