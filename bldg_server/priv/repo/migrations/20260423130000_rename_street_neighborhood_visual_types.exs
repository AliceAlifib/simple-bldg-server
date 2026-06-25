defmodule BldgServer.Repo.Migrations.RenameStreetNeighborhoodVisualTypes do
  use Ecto.Migration

  def up do
    # `street` and `neighborhood` referred to 3d objects rather than semantic
    # entities; rename to `name` and `heading` respectively.
    execute "UPDATE bldgs SET entity_type = 'name' WHERE entity_type = 'street'"
    execute "UPDATE bldgs SET entity_type = 'heading' WHERE entity_type = 'neighborhood'"

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('name', visual_language->'street')
    WHERE visual_language IS NOT NULL AND visual_language ? 'street'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('heading', visual_language->'neighborhood')
    WHERE visual_language IS NOT NULL AND visual_language ? 'neighborhood'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language - 'street' - 'neighborhood'
    WHERE visual_language IS NOT NULL AND (visual_language ? 'street' OR visual_language ? 'neighborhood')
    """
  end

  def down do
    execute "UPDATE bldgs SET entity_type = 'street' WHERE entity_type = 'name'"
    execute "UPDATE bldgs SET entity_type = 'neighborhood' WHERE entity_type = 'heading'"

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('street', visual_language->'name')
    WHERE visual_language IS NOT NULL AND visual_language ? 'name'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language || jsonb_build_object('neighborhood', visual_language->'heading')
    WHERE visual_language IS NOT NULL AND visual_language ? 'heading'
    """

    execute """
    UPDATE bldgs SET visual_language = visual_language - 'name' - 'heading'
    WHERE visual_language IS NOT NULL AND (visual_language ? 'name' OR visual_language ? 'heading')
    """
  end
end
