defmodule BldgServer.Repo.Migrations.IndexBldgsBldgUrl do
  use Ecto.Migration

  def change do
    # `Buildings.get_by_bldg_url/1` is what a battery calls before every build
    # to stay idempotent, and without an index each call read the whole table.
    # Deliberately not unique: the changeset names a unique constraint, but the
    # column never had one and existing rows were not checked for duplicates.
    create index(:bldgs, [:bldg_url])
  end
end
