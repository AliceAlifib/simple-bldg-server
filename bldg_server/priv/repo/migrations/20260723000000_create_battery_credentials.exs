defmodule BldgServer.Repo.Migrations.CreateBatteryCredentials do
  use Ecto.Migration

  def change do
    create table(:battery_credentials) do
      add :battery_type, :string, null: false
      add :owner_email, :string, null: false
      # SHA-256 hash of the plaintext key (never store the key itself).
      add :api_key_hash, :string, null: false

      timestamps()
    end

    create unique_index(:battery_credentials, [:api_key_hash])
    create index(:battery_credentials, [:battery_type])
  end
end
