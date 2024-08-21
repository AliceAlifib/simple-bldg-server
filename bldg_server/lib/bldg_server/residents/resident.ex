defmodule BldgServer.Residents.Resident do
  use Ecto.Schema
  import Ecto.Changeset

  schema "residents" do
    field :alias, :string
    field :direction, :integer
    field :email, :string
    field :flr, :string
    field :home_bldg, :string
    field :is_online, :boolean, default: false
    field :last_login_at, :naive_datetime
    field :location, :string
    field :name, :string
    field :other_attributes, :map
    field :previous_messages, {:array, :string}
    field :session_id, Ecto.UUID
    field :x, :integer
    field :y, :integer
    field :flr_url, :string
    field :nesting_depth, :integer

    timestamps()
  end

  @doc false
  def changeset(resident, attrs) do
    resident
    |> cast(attrs, [:email, :alias, :name, :home_bldg, :is_online, :location, :direction, :previous_messages, :other_attributes, :session_id, :last_login_at, :flr, :flr_url, :x, :y, :nesting_depth])
    |> validate_required([:email, :alias, :name, :home_bldg])
    |> unique_constraint(:email)
  end
end
