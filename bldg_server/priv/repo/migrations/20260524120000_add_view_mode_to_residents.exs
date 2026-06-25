defmodule BldgServer.Repo.Migrations.AddViewModeToResidents do
  use Ecto.Migration

  def change do
    alter table(:residents) do
      # Per-user UI preference: "bird_eye" (default — orthographic top-down)
      # or "immersive" (first-person). Surfaced through the action protocol
      # via the `change_view_mode` action; clients hydrate from the resident
      # payload on login + Phoenix `resident_updated` broadcasts.
      add :view_mode, :string, default: "bird_eye", null: false
    end
  end
end
