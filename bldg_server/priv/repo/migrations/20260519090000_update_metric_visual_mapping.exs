defmodule BldgServer.Repo.Migrations.UpdateMetricVisualMapping do
  use Ecto.Migration

  def up do
    execute """
    UPDATE bldgs
    SET visual_language = jsonb_set(
      visual_language,
      '{metric}',
      '{"3d_object": "metricDisplay", "flr_height": "0.9", "flr0_height": "0.022"}'::jsonb
    )
    WHERE visual_language IS NOT NULL AND visual_language ? 'metric'
    """
  end

  def down do
    execute """
    UPDATE bldgs
    SET visual_language = jsonb_set(
      visual_language,
      '{metric}',
      '{"3d_object": "car", "flr_height": "0.9", "flr0_height": "0.022"}'::jsonb
    )
    WHERE visual_language IS NOT NULL AND visual_language ? 'metric'
    """
  end
end
