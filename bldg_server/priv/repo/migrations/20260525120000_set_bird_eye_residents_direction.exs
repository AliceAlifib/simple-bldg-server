defmodule BldgServer.Repo.Migrations.SetBirdEyeResidentsDirection do
  use Ecto.Migration

  def up do
    # Bird-eye view pins facing to 180 ("facing the objects"); backfill existing
    # bird-eye residents whose direction was left at an arbitrary value.
    execute "UPDATE residents SET direction = 180 WHERE view_mode = 'bird_eye'"
  end

  def down do
    # No-op: original per-resident directions aren't recoverable.
    :ok
  end
end
