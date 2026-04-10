defmodule BldgServer.Repo.Migrations.RenameVisualEntityTypes do
  use Ecto.Migration

  def up do
    # Rename non-semantic entity_types to semantic names
    execute "UPDATE bldgs SET entity_type = 'milestone' WHERE entity_type = 'blue-lot'"
    execute "UPDATE bldgs SET entity_type = 'enabler' WHERE entity_type = 'green-lot'"
    execute "UPDATE bldgs SET entity_type = 'goal' WHERE entity_type = 'problem'"

    # Add new semantic keys to stored visual_language maps on container bldgs
    # so the client can look up children by their new entity_type
    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('milestone', visual_language->'blue-lot')
    WHERE visual_language IS NOT NULL AND visual_language ? 'blue-lot'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('enabler', visual_language->'green-lot')
    WHERE visual_language IS NOT NULL AND visual_language ? 'green-lot'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('goal', visual_language->'problem')
    WHERE visual_language IS NOT NULL AND visual_language ? 'problem'
    """
  end

  def down do
    # Revert semantic entity_types back to visual names
    execute "UPDATE bldgs SET entity_type = 'blue-lot' WHERE entity_type = 'milestone'"
    execute "UPDATE bldgs SET entity_type = 'green-lot' WHERE entity_type = 'enabler'"
    execute "UPDATE bldgs SET entity_type = 'problem' WHERE entity_type = 'goal'"
  end
end
