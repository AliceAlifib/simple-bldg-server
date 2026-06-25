defmodule BldgServer.Repo.Migrations.AddArtifactAndDescriptionVisualMappings do
  use Ecto.Migration

  def up do
    # Add new mappings to existing visual_language maps:
    # artifact -> documentDisplay
    # description -> whiteboard

    execute """
    UPDATE bldgs SET visual_language = visual_language ||
      '{"artifact": {"3d_object": "documentDisplay"}, "description": {"3d_object": "whiteboard"}}'::jsonb
    WHERE visual_language IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE bldgs SET visual_language = visual_language - 'artifact' - 'description'
    WHERE visual_language IS NOT NULL
    """
  end
end
