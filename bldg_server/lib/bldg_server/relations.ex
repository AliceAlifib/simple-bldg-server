defmodule BldgServer.Relations do
  @moduledoc """
  The Relations context.
  """

  import Ecto.Query, warn: false
  alias BldgServer.Repo

  alias BldgServer.Relations.Road
  alias BldgServer.Relations.Marker

  @doc """
  Returns the list of roads.

  ## Examples

      iex> list_roads()
      [%Road{}, ...]

  """
  def list_roads do
    Repo.all(Road)
  end

  @doc """
  Returns all roads inside a given flr.

  Returns empty list if no such road exists.
  """
  def list_roads_in_flr(flr) do
    q = from r in Road, where: r.flr == ^flr
    Repo.all(q)
  end

    @doc """
  Returns all roads (incliuding nested) inside a given flr.

  Returns empty list if no such road exists.
  """
  def list_all_roads_in_flr(flr) do
    # Delimiter-safe: exact floor or a strict sub-path, so ".../l1" doesn't also
    # match ".../l10". See Buildings.list_all_bldgs_in_flr/2.
    flr_subtree = Utils.escape_like_pattern(flr) <> "/%"
    q = from r in Road,
        where: r.flr == ^flr or like(r.flr, ^flr_subtree)
    Repo.all(q)
  end

  @doc """
  Returns all roads that reference the given bldg address as either endpoint.
  """
  def list_roads_connected_to(address) do
    q = from r in Road,
        where: r.from_address == ^address or r.to_address == ^address
    Repo.all(q)
  end

  @doc """
  Cascades a bldg's relocation into each connected road: rewrites stale
  `from_address`/`to_address` strings and the cached `from_x`/`from_y`/`to_x`/
  `to_y` coordinates so roads follow the bldg to its new location. If the
  road lived on the bldg's previous flr, it also follows the bldg to the new
  flr so it renders alongside.
  """
  def cascade_bldg_relocation(old_address, old_flr, %BldgServer.Buildings.Bldg{} = new_bldg) do
    old_address
    |> list_roads_connected_to()
    |> Enum.each(fn road ->
      attrs = relocation_attrs(road, old_address, old_flr, new_bldg)
      if map_size(attrs) > 0, do: update_road(road, attrs)
    end)
  end

  defp relocation_attrs(road, old_address, old_flr, new_bldg) do
    from_changes =
      if road.from_address == old_address,
        do: %{"from_address" => new_bldg.address, "from_x" => new_bldg.x, "from_y" => new_bldg.y},
        else: %{}

    to_changes =
      if road.to_address == old_address,
        do: %{"to_address" => new_bldg.address, "to_x" => new_bldg.x, "to_y" => new_bldg.y},
        else: %{}

    flr_changes =
      if road.flr == old_flr and road.flr != new_bldg.flr,
        do: %{"flr" => new_bldg.flr},
        else: %{}

    from_changes |> Map.merge(to_changes) |> Map.merge(flr_changes)
  end


  @doc """
  Gets a single road.

  Raises `Ecto.NoResultsError` if the Road does not exist.

  ## Examples

      iex> get_road!(123)
      %Road{}

      iex> get_road!(456)
      ** (Ecto.NoResultsError)

  """
  def get_road!(id), do: Repo.get!(Road, id)

  @doc """
  Finds an existing road on a floor between two endpoints (same direction), or
  nil. Used to make `/connect` idempotent so re-emitting identical roads (watch /
  re-render passes) doesn't accumulate duplicates.
  """
  def find_road(flr, from_address, to_address) do
    # NB: the Road schema column is `flr` (there is no `flr_url` on roads) —
    # `create_road` stores the say-floor address here. Querying `flr_url` raises
    # `field flr_url does not exist`, which crashed every /connect and stopped
    # roads from being created on re-render.
    Repo.get_by(Road,
      flr: flr,
      from_address: from_address,
      to_address: to_address
    )
  end

  @doc """
  Creates a road.

  ## Examples

      iex> create_road(%{field: value})
      {:ok, %Road{}}

      iex> create_road(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_road(attrs \\ %{}) do
    result =
      %Road{}
      |> Road.changeset(attrs)
      |> Repo.insert()

    broadcast_road_change(result, "road_created")
    result
  end

  @doc """
  Updates a road.

  ## Examples

      iex> update_road(road, %{field: new_value})
      {:ok, %Road{}}

      iex> update_road(road, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_road(%Road{} = road, attrs) do
    result =
      road
      |> Road.changeset(attrs)
      |> Repo.update()

    broadcast_road_change(result, "road_updated")
    result
  end

  @doc """
  Deletes a road.

  ## Examples

      iex> delete_road(road)
      {:ok, %Road{}}

      iex> delete_road(road)
      {:error, %Ecto.Changeset{}}

  """
  def delete_road(%Road{} = road) do
    flr = road.flr
    road_id = road.id
    result = Repo.delete(road)

    case result do
      {:ok, _} ->
        BldgServer.Buildings.broadcast_to_floor_and_ancestors(flr, "road_deleted", %{id: road_id})
      _ ->
        :ok
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking road changes.

  ## Examples

      iex> change_road(road)
      %Ecto.Changeset{data: %Road{}}

  """
  def change_road(%Road{} = road, attrs \\ %{}) do
    Road.changeset(road, attrs)
  end

  defp broadcast_road_change({:ok, %Road{} = road}, event) do
    payload = BldgServerWeb.FloorChannel.serialize_road(road)
    BldgServer.Buildings.broadcast_to_floor_and_ancestors(road.flr, event, payload)
  end

  defp broadcast_road_change(_, _), do: :ok

  # ---------------------------------------------------------------------------
  # Markers — floor-level geometric idioms (path polylines / area polygons)
  # that, unlike roads, aren't anchored to bldgs. Mirrors the road API.
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of markers.
  """
  def list_markers do
    Repo.all(Marker)
  end

  @doc """
  Returns all markers directly on a given flr (not nested floors).
  """
  def list_markers_in_flr(flr) do
    q = from m in Marker, where: m.flr == ^flr
    Repo.all(q)
  end

  @doc """
  Returns all markers (including nested) inside a given flr.
  """
  def list_all_markers_in_flr(flr) do
    # Delimiter-safe: exact floor or a strict sub-path, so ".../l1" doesn't also
    # match ".../l10". See Buildings.list_all_bldgs_in_flr/2.
    flr_subtree = Utils.escape_like_pattern(flr) <> "/%"

    q =
      from m in Marker,
        where: m.flr == ^flr or like(m.flr, ^flr_subtree)

    Repo.all(q)
  end

  @doc """
  Gets a single marker. Raises `Ecto.NoResultsError` if it does not exist.
  """
  def get_marker!(id), do: Repo.get!(Marker, id)

  @doc """
  Finds the marker named `name` on `flr`, or nil. (flr, name) is the marker's
  identity — see `upsert_marker/1`.
  """
  def find_marker(flr, name) do
    Repo.get_by(Marker, flr: flr, name: name)
  end

  @doc """
  Creates a marker.
  """
  def create_marker(attrs \\ %{}) do
    result =
      %Marker{}
      |> Marker.changeset(attrs)
      |> Repo.insert()

    broadcast_marker_change(result, "marker_created")
    result
  end

  @doc """
  Updates a marker.
  """
  def update_marker(%Marker{} = marker, attrs) do
    result =
      marker
      |> Marker.changeset(attrs)
      |> Repo.update()

    broadcast_marker_change(result, "marker_updated")
    result
  end

  @doc """
  Creates or updates the marker identified by `(flr, name)` in `attrs`.

  Idempotent: re-emitting an identical marker (watch / re-render passes) is a
  no-op — no write, no broadcast — so repeated `/mark` says don't churn the
  floor channel. A changed geometry/color/class/type updates the existing row
  in place (same id), so clients can key on it.
  """
  def upsert_marker(attrs) do
    attrs = stringify_keys(attrs)

    case find_marker(attrs["flr"], attrs["name"]) do
      nil ->
        create_marker(attrs)

      %Marker{} = existing ->
        if marker_unchanged?(existing, attrs) do
          {:ok, existing}
        else
          update_marker(existing, attrs)
        end
    end
  end

  @upsert_compared_fields ~w(xs ys color marker_class marker_type)

  defp marker_unchanged?(%Marker{} = existing, attrs) do
    Enum.all?(@upsert_compared_fields, fn field ->
      # An attribute that's absent from the upsert payload isn't a change.
      not Map.has_key?(attrs, field) or
        Map.get(existing, String.to_existing_atom(field)) == attrs[field]
    end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Deletes a marker.
  """
  def delete_marker(%Marker{} = marker) do
    flr = marker.flr
    marker_id = marker.id
    result = Repo.delete(marker)

    case result do
      {:ok, _} ->
        BldgServer.Buildings.broadcast_to_floor_and_ancestors(flr, "marker_deleted", %{
          id: marker_id
        })

      _ ->
        :ok
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking marker changes.
  """
  def change_marker(%Marker{} = marker, attrs \\ %{}) do
    Marker.changeset(marker, attrs)
  end

  defp broadcast_marker_change({:ok, %Marker{} = marker}, event) do
    payload = BldgServerWeb.FloorChannel.serialize_marker(marker)
    BldgServer.Buildings.broadcast_to_floor_and_ancestors(marker.flr, event, payload)
  end

  defp broadcast_marker_change(_, _), do: :ok
end
