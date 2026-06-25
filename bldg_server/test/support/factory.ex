defmodule BldgServer.Factory do
  @moduledoc """
  Test data builders for the core schemas.

  Builders insert records **directly via Repo** (bypassing the notify/broadcast
  side effects baked into the context `create_*` functions) so tests can set up
  state cheaply and deterministically. Tests that exercise a `create_*` code
  path itself should call the context function directly, not these builders.

  Coordinates/emails default to unique values to avoid `unique_constraint`
  collisions when a test builds several records without specifying them.
  """

  alias BldgServer.Repo
  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg
  alias BldgServer.Residents.Resident
  alias BldgServer.Relations.Road
  alias BldgServer.Batteries.Battery
  alias BldgServer.ResidentsAuth.Session

  @doc "A process-unique positive integer (handy for unique coords / ids)."
  def unique_integer, do: System.unique_integer([:positive])

  @doc """
  Address (and default bldg_url) for a bldg at (x,y) on `flr`.

      bldg_addr("g", 1, 2)            #=> "g/b(1,2)"
      bldg_addr("g/b(3,4)/l0", 1, 2)  #=> "g/b(3,4)/l0/b(1,2)"
  """
  def bldg_addr(flr, x, y), do: "#{flr}/b(#{x},#{y})"

  @doc """
  Insert the root ground floor `g` if absent and return it. Required before any
  test that calls `Buildings.create_bldg/1` for a bldg rooted directly on `g`,
  because `notify_bldg_created/4` looks up the container floor.
  """
  def seed_ground_floor do
    case Buildings.get_by_bldg_url("g") do
      nil ->
        bldg(%{
          "address" => "g",
          "bldg_url" => "g",
          "web_url" => "g",
          "flr" => "g",
          "flr_url" => "g",
          "is_composite" => true,
          "name" => "ground",
          "entity_type" => "ground",
          "x" => 0,
          "y" => 0,
          "visual_language" => Buildings.default_visual_language()
        })

      g ->
        g
    end
  end

  @doc "Build & insert a Bldg. Accepts string- or atom-keyed overrides."
  def bldg(overrides \\ %{}) do
    o = stringify(overrides)
    x = o["x"] || unique_integer()
    y = o["y"] || 1
    flr = o["flr"] || "g"
    address = o["address"] || bldg_addr(flr, x, y)

    defaults = %{
      "address" => address,
      "bldg_url" => address,
      "web_url" => address,
      "flr" => flr,
      "flr_url" => flr,
      "flr_level" => 0,
      "nesting_depth" => 0,
      "x" => x,
      "y" => y,
      "is_composite" => false,
      "name" => "bldg-#{x}-#{y}",
      "entity_type" => "building"
    }

    %Bldg{}
    |> Bldg.changeset(Map.merge(defaults, o))
    |> Repo.insert!()
  end

  @doc "Build & insert a Resident."
  def resident(overrides \\ %{}) do
    n = unique_integer()

    defaults = %{
      email: "user#{n}@example.com",
      alias: "alias-#{n}",
      name: "name-#{n}",
      home_bldg: "g",
      is_online: true,
      direction: 180,
      location: "g",
      flr: "g",
      x: 1,
      y: 1,
      view_mode: "bird_eye"
    }

    %Resident{}
    |> Resident.changeset(Map.merge(defaults, atomize(overrides)))
    |> Repo.insert!()
  end

  @doc "Build & insert a Road."
  def road(overrides \\ %{}) do
    defaults = %{
      flr: "g",
      from_address: "g/b(1,1)",
      to_address: "g/b(2,2)",
      from_x: 1,
      from_y: 1,
      to_x: 2,
      to_y: 2
    }

    %Road{}
    |> Road.changeset(Map.merge(defaults, atomize(overrides)))
    |> Repo.insert!()
  end

  @doc "Build & insert a Battery."
  def battery(overrides \\ %{}) do
    n = unique_integer()

    defaults = %{
      battery_type: "type-#{n}",
      battery_vendor: "vendor",
      battery_version: "1",
      bldg_url: bldg_addr("g", n, 1),
      callback_url: "http://localhost/cb-#{n}",
      flr: "g",
      is_attached: false,
      direct_only: false
    }

    %Battery{}
    |> Battery.changeset(Map.merge(defaults, atomize(overrides)))
    |> Repo.insert!()
  end

  @doc "Build & insert an auth Session."
  def session(overrides \\ %{}) do
    defaults = %{
      session_id: Ecto.UUID.generate(),
      resident_id: unique_integer(),
      email: "user#{unique_integer()}@example.com",
      status: "VERIFIED",
      ip_address: "127.0.0.1",
      last_activity_time: ~N[2020-01-01 00:00:00]
    }

    %Session{}
    |> Session.changeset(Map.merge(defaults, atomize(overrides)))
    |> Repo.insert!()
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp atomize(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
