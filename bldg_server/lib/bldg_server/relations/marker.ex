defmodule BldgServer.Relations.Marker do
  @moduledoc """
  A floor-level geometric marker. Unlike a `Road`, a marker does not connect
  bldgs: it is a free-form polyline (`path`) or closed polygon (`area`) drawn
  through a series of floor cells (`xs`/`ys` are floor-local integer coords,
  pairwise). Markers are keyed by `(flr, name)` so batteries can re-emit them
  idempotently (`Relations.upsert_marker/1`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @marker_types ~w(path area)
  # Same visual classes as roads so the client can reuse its road materials.
  @marker_classes ~w(highway road lane path)

  schema "markers" do
    field :flr, :string
    field :name, :string
    field :marker_type, :string
    field :xs, {:array, :integer}
    field :ys, {:array, :integer}
    field :color, :string
    field :marker_class, :string, default: "road"
    field :owners, {:array, :string}
    field :data, :map

    timestamps()
  end

  @doc false
  def changeset(marker, attrs) do
    marker
    |> cast(attrs, [
      :flr,
      :name,
      :marker_type,
      :xs,
      :ys,
      :color,
      :marker_class,
      :owners,
      :data
    ])
    |> validate_required([:flr, :name, :marker_type, :xs, :ys])
    |> validate_inclusion(:marker_type, @marker_types)
    |> validate_inclusion(:marker_class, @marker_classes)
    |> validate_points()
    |> unique_constraint(:name, name: :markers_flr_name_index)
  end

  # xs/ys must be pairwise (same length), and there must be enough points for
  # the shape: 2+ for a path, 3+ for an area (a closed polygon).
  defp validate_points(changeset) do
    xs = get_field(changeset, :xs)
    ys = get_field(changeset, :ys)
    type = get_field(changeset, :marker_type)

    cond do
      is_nil(xs) or is_nil(ys) ->
        changeset

      length(xs) != length(ys) ->
        add_error(changeset, :ys, "must have the same number of points as xs")

      type == "path" and length(xs) < 2 ->
        add_error(changeset, :xs, "a path needs at least 2 points")

      type == "area" and length(xs) < 3 ->
        add_error(changeset, :xs, "an area needs at least 3 points")

      true ->
        changeset
    end
  end
end
