defmodule BldgServer.Repo.Migrations.AddVisualStylingToBldgs do
  use Ecto.Migration

  def change do
    alter table(:bldgs) do
      # Per-instance visual override. NULL = render with the entity_type's
      # default from the container's visual_language. Color values are
      # named tokens matching the metric-color palette in the bldg-client
      # (same convention as roads.color).
      add :color, :string

      # T-shirt size: XS|S|M|L|XL|XXL. NULL = default size from
      # visual_language. Replaces the previous overload of `category`,
      # which Unity was reading as a size hint.
      add :size, :string

      # Free-form per-entity_type visual variant (e.g. "compact", "tall").
      # Unvalidated for now; tighten per entity_type if a real enum
      # surfaces. NULL = default variant.
      add :variant, :string
    end
  end
end
