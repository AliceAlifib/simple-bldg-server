defmodule BldgServer.Repo.Migrations.WidenBldgTextColumns do
  use Ecto.Migration

  # Ecto's `:string` maps to Postgres `varchar(255)`. A bldg's `bldg_url`,
  # `flr_url` and `address` embed the full nested path (repeated per level), so
  # deeply-nested content (e.g. an artifacts-cabinet leaf:
  # goal/milestone/enabler/task/artifacts/Documents/001) blows past 255 chars —
  # and because command execution is async, the INSERT then failed SILENTLY (the
  # caller already got its 200 while no bldg was created). Widen the columns that
  # can hold long nested paths, URLs or free text to `:text` (no length limit) so
  # those creates succeed. See also the changeset length guard + louder create_bldg.
  def up do
    alter table(:bldgs) do
      modify :bldg_url, :text
      modify :flr_url, :text
      modify :address, :text
      modify :name, :text
      modify :flr, :text
      modify :summary, :text
      modify :web_url, :text
      modify :picture_url, :text
      modify :category, :text
      modify :entity_type, :text
    end
  end

  def down do
    alter table(:bldgs) do
      modify :bldg_url, :string
      modify :flr_url, :string
      modify :address, :string
      modify :name, :string
      modify :flr, :string
      modify :summary, :string
      modify :web_url, :string
      modify :picture_url, :string
      modify :category, :string
      modify :entity_type, :string
    end
  end
end
