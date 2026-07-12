defmodule BldgServer.Buildings.Bldg do
  use Ecto.Schema
  import Ecto.Changeset

  @sizes ~w(XS S M L XL XXL)

  # address/bldg_url/web_url are `:text` (no varchar cap) but are UNIQUE-INDEXED,
  # and a Postgres btree index entry can't exceed ~2704 bytes. Guard well under
  # that so an over-long value fails with a CLEAR changeset error (routed through
  # create_bldg's error logging) instead of crashing the insert — which used to
  # no-op silently. See the widen_bldg_text_columns migration.
  @max_indexed_len 2000

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
    |> validate_length(:bldg_url, max: @max_indexed_len)
    |> validate_length(:address, max: @max_indexed_len)
    |> validate_length(:web_url, max: @max_indexed_len)
    |> validate_inclusion(:size, @sizes)
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
    |> unique_constraint(:address)
    |> unique_constraint(:bldg_url)
  end
end
