defmodule BldgServer.Repo.Migrations.AddMetricVisualMapping do
  use Ecto.Migration

  def up do
    # Add the metric -> car mapping to every existing bldg's visual_language so
    # bldgs created before metrics-battery shipped also know how to render the
    # new entity_type. Mirrors the entry added to @default_visual_language in
    # BldgServer.Buildings.
    execute """
    UPDATE bldgs SET visual_language = visual_language ||
      '{"metric": {"3d_object": "car", "flr_height": "0.9", "flr0_height": "0.022"}}'::jsonb
    WHERE visual_language IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE bldgs SET visual_language = visual_language - 'metric'
    WHERE visual_language IS NOT NULL
    """
  end
end
