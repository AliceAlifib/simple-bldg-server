defmodule BldgServer.Repo.Migrations.BackfillVisualStylingFromStateAndCategory do
  use Ecto.Migration

  # Recognized color tokens currently stored in `state`. Matches the
  # metric-color palette in the bldg-client (case-insensitive).
  @colors ~w(red orange yellow green blue purple pink gray grey black white cyan magenta brown lime teal navy indigo)

  # T-shirt sizes currently stored in `category`. Case-insensitive on read,
  # normalized to uppercase on write.
  @sizes ~w(xs s m l xl xxl)

  def up do
    color_list = Enum.map_join(@colors, ", ", &"'#{&1}'")
    size_list = Enum.map_join(@sizes, ", ", &"'#{&1}'")

    execute("""
    UPDATE bldgs
    SET color = lower(state),
        state = NULL
    WHERE color IS NULL
      AND state IS NOT NULL
      AND lower(state) IN (#{color_list})
    """)

    execute("""
    UPDATE bldgs
    SET size = upper(category),
        category = NULL
    WHERE size IS NULL
      AND category IS NOT NULL
      AND lower(category) IN (#{size_list})
    """)
  end

  def down do
    # Lossy reverse: only restore for rows that don't already have a state /
    # category, to avoid overwriting any values written after the forward
    # migration.
    execute("""
    UPDATE bldgs
    SET state = color,
        color = NULL
    WHERE color IS NOT NULL
      AND state IS NULL
    """)

    execute("""
    UPDATE bldgs
    SET category = size,
        size = NULL
    WHERE size IS NOT NULL
      AND category IS NULL
    """)
  end
end
