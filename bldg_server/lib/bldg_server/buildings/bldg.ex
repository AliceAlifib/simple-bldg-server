defmodule BldgServer.Buildings.Bldg do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bldgs" do
    field(:address, :string)
    field(:category, :string)
    field(:data, :string)
    field(:entity_type, :string)
    field(:flr, :string)
    field(:is_composite, :boolean, default: false)
    field(:name, :string)
    field(:picture_url, :string)
    field(:state, :string)
    field(:summary, :string)
    field(:tags, {:array, :string})
    field(:web_url, :string)
    field(:x, :integer)
    field(:y, :integer)
    field(:owners, {:array, :string})
    field(:bldg_url, :string)
    field(:flr_url, :string)
    field(:flr_level, :integer)
    field(:nesting_depth, :integer)
    field(:previous_messages, {:array, :string})

    timestamps()
  end

  @doc false
  def changeset(bldg, attrs) do
    bldg
    |> cast(attrs, [
      :address,
      :flr,
      :x,
      :y,
      :is_composite,
      :name,
      :web_url,
      :entity_type,
      :state,
      :category,
      :tags,
      :summary,
      :picture_url,
      :data,
      :owners,
      :bldg_url,
      :flr_url,
      :flr_level,
      :nesting_depth,
      :previous_messages
    ])
    |> validate_required([
      :bldg_url,
      :address,
      :x,
      :y,
      :is_composite,
      :name,
      :entity_type,
      :flr_level,
      :nesting_depth
    ])
    |> unique_constraint(:address)
    |> unique_constraint(:bldg_url)
  end
end
