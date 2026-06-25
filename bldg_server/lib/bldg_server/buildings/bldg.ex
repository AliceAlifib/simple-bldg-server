defmodule BldgServer.Buildings.Bldg do
  use Ecto.Schema
  import Ecto.Changeset

  @sizes ~w(XS S M L XL XXL)

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
    field(:width, :integer, default: 1)
    field(:height, :integer, default: 1)
    field(:owners, {:array, :string})
    field(:bldg_url, :string)
    field(:flr_url, :string)
    field(:flr_level, :integer)
    field(:nesting_depth, :integer)
    field(:previous_messages, {:array, :string})
    field(:visual_language, :map)
    field(:favorite_view_points, {:array, :map}, default: [])
    field(:color, :string)
    field(:size, :string)
    field(:variant, :string)

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
      :previous_messages,
      :visual_language,
      :favorite_view_points,
      :color,
      :size,
      :variant,
      :width,
      :height
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
    |> validate_inclusion(:size, @sizes)
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
    |> unique_constraint(:address)
    |> unique_constraint(:bldg_url)
  end
end
