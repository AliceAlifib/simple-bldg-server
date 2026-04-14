defmodule BldgServer.Repo.Migrations.UpdateVisualLanguageMappings do
  use Ecto.Migration

  def up do
    # Update visual_language maps on container bldgs to reflect new mappings:
    # milestone -> raceGate (was blueLot)
    # enabler -> blueLot (was greenLot)
    # task -> greenLot (was pottedPlant, now composite)

    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{milestone}',
      (visual_language->'milestone' || '{"3d_object": "raceGate"}')::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'milestone'
    """

    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{enabler}',
      (visual_language->'enabler' || '{"3d_object": "blueLot"}')::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'enabler'
    """

    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{task}',
      '{"3d_object": "greenLot", "flr_height": "0.9", "flr0_height": "0.022"}'::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'task'
    """
  end

  def down do
    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{milestone}',
      (visual_language->'milestone' || '{"3d_object": "blueLot"}')::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'milestone'
    """

    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{enabler}',
      (visual_language->'enabler' || '{"3d_object": "greenLot"}')::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'enabler'
    """

    execute """
    UPDATE bldgs SET visual_language = jsonb_set(visual_language, '{task}',
      '{"3d_object": "pottedPlant"}'::jsonb)
    WHERE visual_language IS NOT NULL AND visual_language ? 'task'
    """
  end
end
