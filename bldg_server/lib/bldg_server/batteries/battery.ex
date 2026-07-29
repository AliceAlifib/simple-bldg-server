defmodule BldgServer.Batteries.Battery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "batteries" do
    field :battery_type, :string
    field :battery_vendor, :string
    field :battery_version, :string
    field :bldg_url, :string
    field :callback_url, :string
    field :direct_only, :boolean, default: false
    field :flr, :string
    field :is_attached, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(battery, attrs) do
    battery
    |> cast(attrs, [:bldg_url, :flr, :callback_url, :is_attached, :direct_only, :battery_type, :battery_version, :battery_vendor])
    |> validate_required([:bldg_url, :flr, :callback_url])
    |> validate_callback_url()
    |> unique_constraint(:single_attached_battery_in_bldg, name: :single_attached_battery_in_bldg)
  end

  # SSRF guard: the callback_url is later POSTed to by the chat dispatcher, so
  # reject internal/loopback/link-local targets at write time.
  defp validate_callback_url(changeset) do
    validate_change(changeset, :callback_url, fn :callback_url, url ->
      case BldgServer.SafeUrl.validate(url) do
        :ok -> []
        {:error, reason} -> [callback_url: "is unsafe: #{reason}"]
      end
    end)
  end
end
