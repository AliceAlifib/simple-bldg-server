defmodule BldgServer.Relations.Road do
  use Ecto.Schema
  import Ecto.Changeset

  @road_classes ~w(highway road lane path)

  schema "roads" do
    field :flr, :string
    field :from_address, :string
    field :to_address, :string
    field :from_x, :integer
    field :from_y, :integer
    field :to_x, :integer
    field :to_y, :integer
    field :owners, {:array, :string}
    field :color, :string
    field :road_class, :string, default: "road"

    timestamps()
  end

  @doc false
  def changeset(road, attrs) do
    road
    |> cast(attrs, [
      :flr,
      :from_address,
      :to_address,
      :from_x,
      :from_y,
      :to_x,
      :to_y,
      :owners,
      :color,
      :road_class
    ])
    |> validate_required([:flr, :from_address, :to_address, :from_x, :from_y, :to_x, :to_y])
    |> validate_inclusion(:road_class, @road_classes)
  end
end
