defmodule BldgServer.RelationsTest do
  use BldgServer.DataCase

  alias BldgServer.Relations

  describe "roads" do
    alias BldgServer.Relations.Road

    @valid_attrs %{flr: "some flr", from_address: "some from_address", to_address: "some to_address", from_x: 1, from_y: 1, to_x: 2, to_y: 2}
    @update_attrs %{flr: "some updated flr", from_address: "some updated from_address", to_address: "some updated to_address", from_x: 3, from_y: 3, to_x: 4, to_y: 4}
    @invalid_attrs %{flr: nil, from_address: nil, to_address: nil, from_x: nil, from_y: nil, to_x: nil, to_y: nil}

    def road_fixture(attrs \\ %{}) do
      {:ok, road} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Relations.create_road()

      road
    end

    test "list_roads/0 returns all roads" do
      road = road_fixture()
      assert Relations.list_roads() == [road]
    end

    test "get_road!/1 returns the road with given id" do
      road = road_fixture()
      assert Relations.get_road!(road.id) == road
    end

    test "create_road/1 with valid data creates a road" do
      assert {:ok, %Road{} = road} = Relations.create_road(@valid_attrs)
      assert road.flr == "some flr"
      assert road.from_address == "some from_address"
      assert road.to_address == "some to_address"
    end

    test "create_road/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Relations.create_road(@invalid_attrs)
    end

    test "update_road/2 with valid data updates the road" do
      road = road_fixture()
      assert {:ok, %Road{} = road} = Relations.update_road(road, @update_attrs)
      assert road.flr == "some updated flr"
      assert road.from_address == "some updated from_address"
      assert road.to_address == "some updated to_address"
    end

    test "update_road/2 with invalid data returns error changeset" do
      road = road_fixture()
      assert {:error, %Ecto.Changeset{}} = Relations.update_road(road, @invalid_attrs)
      assert road == Relations.get_road!(road.id)
    end

    test "delete_road/1 deletes the road" do
      road = road_fixture()
      assert {:ok, %Road{}} = Relations.delete_road(road)
      assert_raise Ecto.NoResultsError, fn -> Relations.get_road!(road.id) end
    end

    test "change_road/1 returns a road changeset" do
      road = road_fixture()
      assert %Ecto.Changeset{} = Relations.change_road(road)
    end
  end

  describe "road cascade on bldg relocation" do
    alias BldgServer.Buildings
    alias BldgServer.Relations.Road

    # Use flr values without "/" so get_container returns "" and the
    # notify_bldg_created/updated hierarchy walk is a no-op — otherwise the
    # walk tries to get_bldg! on parent floors we don't seed.
    @bldg_base %{
      category: "c",
      entity_type: "e",
      is_composite: false,
      picture_url: "p",
      state: "s",
      summary: "sum",
      tags: [],
      web_url: "w",
      flr_level: 0,
      nesting_depth: 1,
      owners: [],
      flr_url: "testflr"
    }

    defp bldg!(overrides) do
      attrs =
        @bldg_base
        |> Map.merge(overrides)
        |> Map.put_new(:bldg_url, overrides[:address])

      {:ok, bldg} = Buildings.create_bldg(attrs)
      bldg
    end

    defp road_between(a, b) do
      {:ok, road} =
        Relations.create_road(%{
          flr: a.flr,
          from_address: a.address,
          to_address: b.address,
          from_x: a.x,
          from_y: a.y,
          to_x: b.x,
          to_y: b.y
        })
      road
    end

    test "relocating the `from` endpoint rewrites from_address and coords, leaves `to` untouched" do
      a = bldg!(%{address: "g/b(1,1)", flr: "testflr", x: 1, y: 1, name: "a"})
      b = bldg!(%{address: "g/b(5,5)", flr: "testflr", x: 5, y: 5, name: "b"})
      road = road_between(a, b)

      {:ok, _} = Buildings.update_bldg(a, %{"address" => "g/b(2,2)", "x" => 2, "y" => 2})

      updated = Relations.get_road!(road.id)
      assert updated.from_address == "g/b(2,2)"
      assert updated.from_x == 2
      assert updated.from_y == 2
      assert updated.to_address == "g/b(5,5)"
      assert updated.to_x == 5
      assert updated.to_y == 5
    end

    test "relocating the `to` endpoint rewrites to_address and coords" do
      a = bldg!(%{address: "g/b(1,1)", flr: "testflr", x: 1, y: 1, name: "a2"})
      b = bldg!(%{address: "g/b(5,5)", flr: "testflr", x: 5, y: 5, name: "b2"})
      road = road_between(a, b)

      {:ok, _} = Buildings.update_bldg(b, %{"address" => "g/b(9,9)", "x" => 9, "y" => 9})

      updated = Relations.get_road!(road.id)
      assert updated.to_address == "g/b(9,9)"
      assert updated.to_x == 9
      assert updated.to_y == 9
      assert updated.from_address == "g/b(1,1)"
    end

    test "a relocation that changes flr carries roads on the old flr to the new one" do
      a = bldg!(%{address: "g/b(1,1)", flr: "testflr", x: 1, y: 1, name: "a3"})
      b = bldg!(%{address: "g/b(5,5)", flr: "testflr", x: 5, y: 5, name: "b3"})
      road = road_between(a, b)

      {:ok, _} =
        Buildings.update_bldg(a, %{
          "address" => "newflr-a3",
          "x" => 1,
          "y" => 1,
          "flr" => "newflr"
        })

      updated = Relations.get_road!(road.id)
      assert updated.flr == "newflr"
      assert updated.from_address == "newflr-a3"
    end

    test "non-relocating update (no address change) does not touch roads" do
      a = bldg!(%{address: "g/b(1,1)", flr: "testflr", x: 1, y: 1, name: "a4"})
      b = bldg!(%{address: "g/b(5,5)", flr: "testflr", x: 5, y: 5, name: "b4"})
      road = road_between(a, b)

      {:ok, _} = Buildings.update_bldg(a, %{"summary" => "edited"})

      unchanged = Relations.get_road!(road.id)
      assert unchanged.from_address == "g/b(1,1)"
      assert unchanged.from_x == 1
      assert unchanged.from_y == 1
    end
  end
end
