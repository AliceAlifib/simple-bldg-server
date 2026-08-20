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

  describe "markers" do
    alias BldgServer.Relations.Marker

    @marker_valid_attrs %{
      flr: "g/b(1,1)/l0",
      name: "spine",
      marker_type: "path",
      xs: [0, 5, 10],
      ys: [0, 0, 0],
      color: "blue",
      marker_class: "lane"
    }
    @marker_update_attrs %{color: "red", xs: [0, 5, 10, 15], ys: [0, 1, 2, 3]}
    @marker_invalid_attrs %{flr: nil, name: nil, marker_type: nil, xs: nil, ys: nil}

    def marker_fixture(attrs \\ %{}) do
      {:ok, marker} =
        attrs
        |> Enum.into(@marker_valid_attrs)
        |> Relations.create_marker()

      marker
    end

    test "list_markers/0 returns all markers" do
      marker = marker_fixture()
      assert Relations.list_markers() == [marker]
    end

    test "get_marker!/1 returns the marker with given id" do
      marker = marker_fixture()
      assert Relations.get_marker!(marker.id) == marker
    end

    test "create_marker/1 with valid data creates a marker" do
      assert {:ok, %Marker{} = marker} = Relations.create_marker(@marker_valid_attrs)
      assert marker.flr == "g/b(1,1)/l0"
      assert marker.name == "spine"
      assert marker.marker_type == "path"
      assert marker.xs == [0, 5, 10]
      assert marker.ys == [0, 0, 0]
      assert marker.color == "blue"
      assert marker.marker_class == "lane"
    end

    test "create_marker/1 defaults marker_class to \"road\"" do
      {:ok, marker} = Relations.create_marker(Map.delete(@marker_valid_attrs, :marker_class))
      assert marker.marker_class == "road"
    end

    test "create_marker/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Relations.create_marker(@marker_invalid_attrs)
    end

    test "create_marker/1 rejects an unknown marker_type or marker_class" do
      assert {:error, cs} = Relations.create_marker(%{@marker_valid_attrs | marker_type: "blob"})
      assert %{marker_type: _} = errors_on(cs)

      assert {:error, cs} =
               Relations.create_marker(%{@marker_valid_attrs | marker_class: "river"})
      assert %{marker_class: _} = errors_on(cs)
    end

    test "create_marker/1 rejects mismatched xs/ys lengths" do
      assert {:error, cs} = Relations.create_marker(%{@marker_valid_attrs | ys: [0, 0]})
      assert %{ys: _} = errors_on(cs)
    end

    test "create_marker/1 enforces 2+ points for a path and 3+ for an area" do
      assert {:error, cs} = Relations.create_marker(%{@marker_valid_attrs | xs: [1], ys: [1]})
      assert %{xs: _} = errors_on(cs)

      assert {:error, cs} =
               Relations.create_marker(%{
                 @marker_valid_attrs
                 | marker_type: "area",
                   xs: [0, 1],
                   ys: [0, 1]
               })

      assert %{xs: _} = errors_on(cs)

      assert {:ok, %Marker{marker_type: "area"}} =
               Relations.create_marker(%{
                 @marker_valid_attrs
                 | marker_type: "area",
                   xs: [0, 1, 1],
                   ys: [0, 0, 1]
               })
    end

    test "create_marker/1 enforces (flr, name) uniqueness" do
      marker_fixture()
      assert {:error, cs} = Relations.create_marker(@marker_valid_attrs)
      assert %{name: _} = errors_on(cs)

      # same name on a different floor is fine
      assert {:ok, _} = Relations.create_marker(%{@marker_valid_attrs | flr: "g/b(2,2)/l0"})
    end

    test "update_marker/2 with valid data updates the marker" do
      marker = marker_fixture()
      assert {:ok, %Marker{} = marker} = Relations.update_marker(marker, @marker_update_attrs)
      assert marker.color == "red"
      assert marker.xs == [0, 5, 10, 15]
      assert marker.ys == [0, 1, 2, 3]
    end

    test "update_marker/2 with invalid data returns error changeset" do
      marker = marker_fixture()
      assert {:error, %Ecto.Changeset{}} = Relations.update_marker(marker, @marker_invalid_attrs)
      assert marker == Relations.get_marker!(marker.id)
    end

    test "delete_marker/1 deletes the marker" do
      marker = marker_fixture()
      assert {:ok, %Marker{}} = Relations.delete_marker(marker)
      assert_raise Ecto.NoResultsError, fn -> Relations.get_marker!(marker.id) end
    end

    test "change_marker/1 returns a marker changeset" do
      marker = marker_fixture()
      assert %Ecto.Changeset{} = Relations.change_marker(marker)
    end

    test "find_marker/2 finds by (flr, name) or returns nil" do
      marker = marker_fixture()
      assert Relations.find_marker(marker.flr, marker.name).id == marker.id
      assert Relations.find_marker(marker.flr, "nope") == nil
      assert Relations.find_marker("g/elsewhere/l0", marker.name) == nil
    end

    test "list_markers_in_flr/1 is direct-only; list_all_markers_in_flr/1 includes nested" do
      direct = marker(%{flr: "g/b(1,2)/l0"})
      nested = marker(%{flr: "g/b(1,2)/l0/b(3,4)/l0"})
      _other = marker(%{flr: "g/b(9,9)/l0"})

      assert Relations.list_markers_in_flr("g/b(1,2)/l0") |> Enum.map(& &1.id) == [direct.id]

      ids = Relations.list_all_markers_in_flr("g/b(1,2)/l0") |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([direct.id, nested.id])
    end

    test "list_all_markers_in_flr/1 is delimiter-safe (l1 does not match l10)" do
      on_l1 = marker(%{flr: "g/b(1,2)/l1"})
      _on_l10 = marker(%{flr: "g/b(1,2)/l10"})

      ids = Relations.list_all_markers_in_flr("g/b(1,2)/l1") |> Enum.map(& &1.id)
      assert ids == [on_l1.id]
    end
  end

  describe "upsert_marker/1" do
    @upsert_attrs %{
      "flr" => "g/b(1,1)/l0",
      "name" => "lane-a",
      "marker_type" => "path",
      "xs" => [0, 4],
      "ys" => [0, 4],
      "color" => "green",
      "marker_class" => "lane",
      "owners" => ["o@test.com"]
    }

    test "creates when no marker with that (flr, name) exists" do
      assert {:ok, marker} = Relations.upsert_marker(@upsert_attrs)
      assert marker.name == "lane-a"
      assert length(Relations.list_markers()) == 1
    end

    test "an identical second call is a no-op: same id, no new row, no timestamp bump" do
      {:ok, first} = Relations.upsert_marker(@upsert_attrs)
      {:ok, second} = Relations.upsert_marker(@upsert_attrs)

      assert second.id == first.id
      assert second.updated_at == first.updated_at
      assert length(Relations.list_markers()) == 1
    end

    test "a changed color updates the existing row in place (same id)" do
      {:ok, first} = Relations.upsert_marker(@upsert_attrs)
      {:ok, second} = Relations.upsert_marker(%{@upsert_attrs | "color" => "red"})

      assert second.id == first.id
      assert second.color == "red"
      assert Relations.get_marker!(first.id).color == "red"
      assert length(Relations.list_markers()) == 1
    end

    test "changed points update the existing row in place" do
      {:ok, first} = Relations.upsert_marker(@upsert_attrs)
      {:ok, second} =
        Relations.upsert_marker(%{@upsert_attrs | "xs" => [0, 4, 8], "ys" => [0, 4, 8]})

      assert second.id == first.id
      assert second.xs == [0, 4, 8]
      assert length(Relations.list_markers()) == 1
    end

    test "accepts atom-keyed attrs too" do
      attrs = Map.new(@upsert_attrs, fn {k, v} -> {String.to_atom(k), v} end)
      assert {:ok, first} = Relations.upsert_marker(attrs)
      assert {:ok, second} = Relations.upsert_marker(attrs)
      assert first.id == second.id
    end
  end
end
