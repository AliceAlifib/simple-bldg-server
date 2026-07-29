defmodule BldgServer.Batteries.BatteryCredential do
  @moduledoc """
  A service credential for a battery (a machine caller that can't do the email
  magic-link). Only the SHA-256 hash of the API key is stored; the plaintext key
  is shown once at provisioning. The credential identifies the battery by
  `battery_type` + `owner_email` for authorization.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "battery_credentials" do
    field :battery_type, :string
    field :owner_email, :string
    field :api_key_hash, :string

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:battery_type, :owner_email, :api_key_hash])
    |> validate_required([:battery_type, :owner_email, :api_key_hash])
    |> unique_constraint(:api_key_hash)
  end
end
