defmodule BldgServer.Repo.Migrations.AddNestingDepthToResidents do
  use Ecto.Migration

  def change do
    alter table("residents") do
      add :flr_level, :integer
    end

    alter table("residents") do
      add :nesting_depth, :integer
    end
  end

end
