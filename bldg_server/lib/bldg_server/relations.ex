defmodule BldgServer.Relations do
  @moduledoc """
  The Relations context.
  """

  import Ecto.Query, warn: false
  alias BldgServer.Repo

  alias BldgServer.Relations.Road

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
    q = from r in Road,
        where: r.flr == ^flr or like(r.flr, ^"#{flr}/%")
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
end
