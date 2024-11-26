defmodule BldgServer.Repo.Migrations.RemoveWebUrlUniqueConstraint do
  use Ecto.Migration

  def change do
    drop unique_index(:bldgs, [:web_url])
  end
end
