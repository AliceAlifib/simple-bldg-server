defmodule BldgServer.BuildingsAllocationTest do
  @moduledoc """
  Coverage for auto-placement: the grid scan that finds a free slot
  (`get_next_available_location/4`) and the collision-retry coordinate helpers
  (`replace_bldg_coords/3`, `jitter_bldg_location/1`). These had a missing
  documented fallback (full floor returned nil → crash) and a first-textual-match
  bug in the coordinate rewrite.
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings

  describe "get_next_available_location/4 (existing grid behavior, pinned)" do
    test "finds the next free slot in the start row" do
      assert Buildings.get_next_available_location([{1, 1}, {2, 1}, {4, 1}], {1, 1}, 16, 12) == {3, 1}
    end

    test "wraps to the next row when the start row is full" do
      assert Buildings.get_next_available_location([{14, 5}, {15, 5}, {16, 5}], {14, 5}, 16, 12) == {14, 6}
    end
  end

  describe "get_next_available_location/4 full-floor fallback" do
    test "falls back to one column left of the cluster when the up-right grid is full" do
      # Fill the entire 2x2 grid reachable from start {1,1} up to max {2,2}.
      full = for x <- 1..2, y <- 1..2, do: {x, y}
      assert Buildings.get_next_available_location(full, {1, 1}, 2, 2) == {0, 1}
    end

    test "returns nil only when there is truly no room (start column already at 0)" do
      full = for x <- 0..2, y <- 0..2, do: {x, y}
      assert Buildings.get_next_available_location(full, {0, 0}, 2, 2) == nil
    end
  end

  describe "replace_bldg_coords/3" do
    test "rewrites only the last bldg segment" do
      assert Buildings.replace_bldg_coords("g/b(1,2)", 3, 4) == "g/b(3,4)"
      assert Buildings.replace_bldg_coords("g/b(1,2)/l0/b(5,6)", 7, 8) == "g/b(1,2)/l0/b(7,8)"
    end

    test "does not corrupt an ancestor segment that shares the same coords" do
      # Both the ancestor and the leaf are b(5,5); only the leaf must change.
      assert Buildings.replace_bldg_coords("g/b(5,5)/l0/b(5,5)", 7, 8) == "g/b(5,5)/l0/b(7,8)"
    end
  end

  describe "jitter_bldg_location/1" do
    test "shifts the last segment within +/-1 on each axis and never goes negative" do
      for _ <- 1..200 do
        result = Buildings.jitter_bldg_location("g/b(0,0)/l0/b(0,3)")
        {x, y} = Buildings.extract_coords(result)
        # origin segment unchanged, leaf within [-1,+1] clamped at 0
        assert String.starts_with?(result, "g/b(0,0)/l0/b(")
        assert x in 0..1
        assert y in 2..4
      end
    end
  end
end
