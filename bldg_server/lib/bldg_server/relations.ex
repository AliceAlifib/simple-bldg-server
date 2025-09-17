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
    q = from r in Road,
        where: like(r.flr, ^"#{flr}%")
    Repo.all(q)
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
  Creates a road.

  ## Examples

      iex> create_road(%{field: value})
      {:ok, %Road{}}

      iex> create_road(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_road(attrs \\ %{}) do
    %Road{}
    |> Road.changeset(attrs)
    |> Repo.insert()
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
    road
    |> Road.changeset(attrs)
    |> Repo.update()
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
    Repo.delete(road)
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
end
