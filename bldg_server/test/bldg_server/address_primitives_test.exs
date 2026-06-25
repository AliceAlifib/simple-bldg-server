defmodule BldgServer.AddressPrimitivesTest do
  @moduledoc """
  Characterization tests for the stringly-typed address primitives that are
  re-implemented across the codebase (`extract_coords/1`, `get_container/1`,
  `extract_flr_level/1`) and the two nesting-depth formulas.

  These PIN current behavior so the planned "centralize address parsing" refactor
  can change it deliberately and see exactly what moves. Where current behavior is
  a rough edge (e.g. raising on malformed input), the test documents it rather
  than asserting it's desirable.
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings
  alias BldgServer.Residents

  describe "extract_coords/1" do
    test "parses the coords from the last bldg segment of an address" do
      assert Buildings.extract_coords("g/b(17,24)") == {17, 24}
      assert Buildings.extract_coords("g/b(17,24)/l0/b(4,5)") == {4, 5}
    end

    test "handles negative and multi-digit coords" do
      assert Buildings.extract_coords("g/b(17,24)/l0/b(-11,6)") == {-11, 6}
      assert Buildings.extract_coords("g/b(123,456)") == {123, 456}
    end

    test "handles zero coords" do
      assert Buildings.extract_coords("g/b(0,0)") == {0, 0}
    end

    # ROUGH EDGE (candidate for the refactor): extract_coords assumes the last
    # segment is a b(x,y) tuple. A floor or the ground address makes the inner
    # pattern match fail with a MatchError — i.e. malformed input currently
    # crashes (a 500 at the API edge) rather than returning a structured error.
    test "raises on a floor address (no bldg tuple in the last segment)" do
      assert_raise MatchError, fn -> Buildings.extract_coords("g/b(1,2)/l0") end
    end

    test "raises on the ground address" do
      assert_raise MatchError, fn -> Buildings.extract_coords("g") end
    end
  end

  describe "get_container/1" do
    test "drops the last segment" do
      assert Buildings.get_container("g/b(17,24)/l0/b(4,5)") == "g/b(17,24)/l0"
      assert Buildings.get_container("g/b(1,2)") == "g"
    end

    test "a single segment has no container (empty string)" do
      assert Buildings.get_container("g") == ""
      assert Buildings.get_container("solo") == ""
    end
  end

  describe "extract_flr_level/1" do
    test "ground is level 0" do
      assert Buildings.extract_flr_level("g") == 0
    end

    test "reads the numeric suffix of the last floor segment" do
      assert Buildings.extract_flr_level("g/b(1,2)/l0") == 0
      assert Buildings.extract_flr_level("g/b(1,2)/l7") == 7
      assert Buildings.extract_flr_level("g/b(1,2)/l0/b(3,4)/l12") == 12
    end
  end

  describe "nesting depth — two intentionally different measurements" do
    # Buildings.calculate_nesting_depth/1 measures a BLDG's own depth (computed
    # over the bldg's address during `build`). Residents.calculate_nesting_depth_
    # from_address/1 is called with the CONTAINER address and measures the depth a
    # resident occupies *inside* it. For a bldg-address the resident value is the
    # bldg value + 1; for a floor/ground address they agree. They are NOT meant to
    # be equal — this table locks that relationship.
    #
    # address                      | bldg depth | resident-inside depth
    @cases [
      {"g",                          0, 0},
      {"g/b(1,2)",                   0, 1},
      {"g/b(1,2)/l0",                1, 1},
      {"g/b(1,2)/l0/b(3,4)",         1, 2},
      {"g/b(1,2)/l0/b(3,4)/l1",      2, 2},
      {"g/b(1,2)/l0/b(3,4)/l1/b(5,6)", 2, 3}
    ]

    test "Buildings.calculate_nesting_depth matches the pinned bldg-depth column" do
      for {address, bldg_depth, _resident_depth} <- @cases do
        result = Buildings.calculate_nesting_depth(%{"address" => address})
        assert result["nesting_depth"] == bldg_depth,
               "#{address}: expected bldg depth #{bldg_depth}, got #{result["nesting_depth"]}"
      end
    end

    test "Residents.calculate_nesting_depth_from_address matches the pinned resident-inside column" do
      for {address, _bldg_depth, resident_depth} <- @cases do
        result = Residents.calculate_nesting_depth_from_address(address)
        assert result == resident_depth,
               "#{address}: expected resident-inside depth #{resident_depth}, got #{result}"
      end
    end

    test "the two formulas differ by exactly 1 on bldg-addresses and agree on floor/ground addresses" do
      for {address, bldg_depth, resident_depth} <- @cases do
        ends_in_bldg = String.match?(address, ~r/b\(\d+,\d+\)$/)
        expected_delta = if ends_in_bldg, do: 1, else: 0
        assert resident_depth - bldg_depth == expected_delta, "mismatch for #{address}"
      end
    end
  end
end
