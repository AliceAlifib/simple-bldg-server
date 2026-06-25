defmodule BldgServer.BuildingsDimensionsTest do
  @moduledoc """
  Bldg footprints: persisted width/height and overlap-aware placement. A bldg
  occupies `x..x+width-1` × `y..y+height-1` on its floor (origin = bottom-left).
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg
  alias BldgServer.Repo

  defp create_attrs(overrides) do
    Map.merge(
      %{
        "flr" => "g",
        "is_composite" => false,
        "entity_type" => "building",
        "flr_level" => 0,
        "nesting_depth" => 0
      },
      overrides
    )
  end

  describe "persistence" do
    test "a bldg persists its width/height footprint" do
      b = bldg(%{address: "g/b(1,1)", bldg_url: "g/b(1,1)", width: 3, height: 2})
      reloaded = Repo.get(Bldg, b.id)
      assert reloaded.width == 3
      assert reloaded.height == 2
    end

    test "width/height default to 1 (the historical point model)" do
      b = bldg(%{address: "g/b(2,2)", bldg_url: "g/b(2,2)"})
      reloaded = Repo.get(Bldg, b.id)
      assert reloaded.width == 1
      assert reloaded.height == 1
    end

    test "the changeset rejects non-positive dimensions" do
      cs = Bldg.changeset(%Bldg{}, %{width: 0, height: -2, address: "g/b(1,1)"})
      refute cs.valid?
      assert %{width: [_ | _], height: [_ | _]} = errors_on(cs)
    end
  end

  describe "footprints_overlap?/2" do
    test "detects intersecting rectangles" do
      assert Buildings.footprints_overlap?(%{x: 1, y: 1, width: 3, height: 3}, %{x: 2, y: 2, width: 2, height: 2})
    end

    test "edge-adjacent rectangles do not overlap" do
      refute Buildings.footprints_overlap?(%{x: 1, y: 1, width: 2, height: 2}, %{x: 3, y: 1, width: 2, height: 2})
    end

    test "fully separate rectangles do not overlap" do
      refute Buildings.footprints_overlap?(%{x: 1, y: 1, width: 1, height: 1}, %{x: 5, y: 5, width: 1, height: 1})
    end
  end

  describe "find_free_footprint/5" do
    test "returns the first slot on an empty floor" do
      assert Buildings.find_free_footprint([], 2, 2, 16, 12) == %{x: 1, y: 1, width: 2, height: 2}
    end

    test "skips past an occupied footprint to the first clear origin" do
      occupied = [%{x: 1, y: 1, width: 3, height: 3}]
      placed = Buildings.find_free_footprint(occupied, 3, 3, 16, 12)
      assert placed == %{x: 4, y: 1, width: 3, height: 3}
      refute Buildings.footprints_overlap?(placed, hd(occupied))
    end

    test "returns nil when a footprint cannot fit within the floor bounds" do
      assert Buildings.find_free_footprint([], 3, 3, 2, 2) == nil
    end

    test "returns nil when the floor is full" do
      occupied = [%{x: 1, y: 1, width: 2, height: 2}]
      assert Buildings.find_free_footprint(occupied, 2, 2, 2, 2) == nil
    end
  end

  describe "auto-placement avoids overlap (decide_on_location)" do
    test "an auto-placed footprint is clear of existing footprints on the floor" do
      flr = "g/b(5,5)/l0"
      existing = %{x: 1, y: 1, width: 3, height: 3}

      bldg(%{
        flr: flr,
        address: "#{flr}/b(1,1)",
        bldg_url: "#{flr}/b(1,1)",
        x: 1,
        y: 1,
        width: 3,
        height: 3
      })

      placed =
        Buildings.decide_on_location(%{
          "flr" => flr,
          "entity_type" => "thing",
          "width" => 3,
          "height" => 3
        })

      new_footprint = %{x: placed["x"], y: placed["y"], width: 3, height: 3}
      refute Buildings.footprints_overlap?(new_footprint, existing)
    end
  end

  describe "create_bldg overlap rejection (explicit placement)" do
    setup do
      seed_ground_floor()
      # A 3x3 bldg covering x:1..3, y:1..3 on the ground floor.
      bldg(%{flr: "g", address: "g/b(1,1)", bldg_url: "g/b(1,1)", x: 1, y: 1, width: 3, height: 3, name: "big"})
      :ok
    end

    test "rejects a create whose footprint overlaps an existing bldg on the floor" do
      # 2x2 at {2,2} covers x:2..3, y:2..3 — intersects the existing 3x3. The
      # address is unique, so only the footprint check can catch this.
      attrs =
        create_attrs(%{
          "address" => "g/b(2,2)",
          "bldg_url" => "g/b(2,2)",
          "name" => "overlapper",
          "x" => 2,
          "y" => 2,
          "width" => 2,
          "height" => 2
        })

      assert {:error, cs} = Buildings.create_bldg(attrs)
      assert Enum.any?(errors_on(cs).address, &(&1 =~ "overlaps"))
    end

    test "allows an edge-adjacent footprint (no overlap)" do
      # 2x2 at {4,1} covers x:4..5 — flush against the existing bldg's right edge.
      attrs =
        create_attrs(%{
          "address" => "g/b(4,1)",
          "bldg_url" => "g/b(4,1)",
          "name" => "neighbor",
          "x" => 4,
          "y" => 1,
          "width" => 2,
          "height" => 2
        })

      assert {:ok, _bldg} = Buildings.create_bldg(attrs)
    end
  end
end
