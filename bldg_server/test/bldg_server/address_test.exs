defmodule BldgServer.AddressTest do
  @moduledoc """
  Tests for the parsed Address representation. Includes a round-trip check over a
  representative corpus and equivalence assertions against the legacy primitives
  the module is intended to replace, so the upcoming delegation is provably
  behavior-preserving.
  """
  use ExUnit.Case, async: true

  alias BldgServer.Address
  alias BldgServer.Buildings
  alias BldgServer.Residents

  # A corpus covering every segment kind: ground, single/deep bldgs, floors,
  # negative and multi-digit coords, and name-aliased bldg_url segments.
  @corpus [
    "g",
    "g/b(1,2)",
    "g/b(1,2)/l0",
    "g/b(1,2)/l0/b(3,4)",
    "g/b(17,24)/l0/b(-11,6)",
    "g/b(123,456)/l12/b(0,0)",
    "g/b(-5,-9)",
    "g/team",
    "g/team/l0/b(1,1)",
    "g/udi-bauman/l0/b(2,3)/l1/b(4,5)"
  ]

  describe "parse/1 and to_string/1" do
    test "round-trips every address in the corpus" do
      for s <- @corpus do
        assert Address.to_string(Address.parse!(s)) == s, "round-trip failed for #{s}"
      end
    end

    test "classifies each segment kind" do
      assert %Address{segments: [:ground, {:bldg, 1, 2}, {:floor, 0}, {:named, "team"}]} =
               Address.parse!("g/b(1,2)/l0/team")
    end

    test "is total over name-aliased bldg_url segments" do
      assert Address.parse!("g/team/l0/b(1,1)").segments ==
               [:ground, {:named, "team"}, {:floor, 0}, {:bldg, 1, 1}]
    end

    test "rejects a blank string" do
      assert Address.parse("") == {:error, :empty}
      assert_raise ArgumentError, fn -> Address.parse!("") end
    end

    test "String.Chars protocol renders the canonical form" do
      assert "#{Address.parse!("g/b(1,2)/l0")}" == "g/b(1,2)/l0"
    end
  end

  describe "coords/1, container/1, floor_level/1" do
    test "coords returns the last bldg segment's tuple, or :error" do
      assert Address.coords(Address.parse!("g/b(17,24)/l0/b(-11,6)")) == {-11, 6}
      assert Address.coords(Address.parse!("g/b(1,2)/l0")) == :error
      assert Address.coords(Address.parse!("g")) == :error
    end

    test "container drops the last segment, :error at the root" do
      assert Address.container(Address.parse!("g/b(1,2)/l0/b(3,4)")) == Address.parse!("g/b(1,2)/l0")
      assert Address.container(Address.parse!("g/b(1,2)")) == Address.parse!("g")
      assert Address.container(Address.parse!("g")) == :error
    end

    test "floor_level: 0 for ground, n for l<n>, :error otherwise" do
      assert Address.floor_level(Address.parse!("g")) == 0
      assert Address.floor_level(Address.parse!("g/b(1,2)/l7")) == 7
      assert Address.floor_level(Address.parse!("g/b(1,2)")) == :error
    end
  end

  describe "hierarchy: ground?/ends_in_bldg?/ancestor?/rebase" do
    test "ground? and ends_in_bldg?" do
      assert Address.ground?(Address.parse!("g"))
      refute Address.ground?(Address.parse!("g/b(1,2)"))
      assert Address.ends_in_bldg?(Address.parse!("g/b(1,2)"))
      refute Address.ends_in_bldg?(Address.parse!("g/b(1,2)/l0"))
    end

    test "ancestor? is strict and prefix-structural (not text-prefix)" do
      anc = Address.parse!("g/b(1,2)/l1")
      assert Address.ancestor?(anc, Address.parse!("g/b(1,2)/l1/b(3,4)"))
      refute Address.ancestor?(anc, anc)
      # the LIKE-prefix hazard: l1 is a TEXT prefix of l10 but NOT an ancestor
      refute Address.ancestor?(anc, Address.parse!("g/b(1,2)/l10/b(3,4)"))
    end

    test "rebase re-roots a descendant from one container to another" do
      d = Address.parse!("g/b(5,5)/l0/b(1,1)/l0/b(2,2)")
      from = Address.parse!("g/b(5,5)")
      to = Address.parse!("g/b(9,9)")
      assert Address.rebase(d, from, to) == Address.parse!("g/b(9,9)/l0/b(1,1)/l0/b(2,2)")
    end

    test "rebase returns :error when `from` is not a prefix" do
      assert Address.rebase(Address.parse!("g/b(1,1)"), Address.parse!("g/b(2,2)"), Address.parse!("g/b(9,9)")) ==
               :error
    end
  end

  describe "equivalence with the legacy primitives (delegation safety net)" do
    test "coords matches Buildings.extract_coords on bldg-terminated addresses" do
      for s <- Enum.filter(@corpus, &String.match?(&1, ~r/b\(-?\d+,-?\d+\)$/)) do
        assert Address.coords(Address.parse!(s)) == Buildings.extract_coords(s), "coords mismatch for #{s}"
      end
    end

    test "container matches Buildings.get_container (with :error mapped to \"\")" do
      for s <- @corpus do
        legacy = Buildings.get_container(s)
        from_addr =
          case Address.container(Address.parse!(s)) do
            :error -> ""
            c -> Address.to_string(c)
          end

        assert from_addr == legacy, "container mismatch for #{s}"
      end
    end

    test "nesting_depth matches Buildings.calculate_nesting_depth" do
      for s <- @corpus do
        assert Address.nesting_depth(Address.parse!(s)) ==
                 Buildings.calculate_nesting_depth(%{"address" => s})["nesting_depth"],
               "bldg nesting depth mismatch for #{s}"
      end
    end

    test "inside_depth matches Residents.calculate_nesting_depth_from_address" do
      for s <- @corpus do
        assert Address.inside_depth(Address.parse!(s)) ==
                 Residents.calculate_nesting_depth_from_address(s),
               "inside depth mismatch for #{s}"
      end
    end
  end
end
