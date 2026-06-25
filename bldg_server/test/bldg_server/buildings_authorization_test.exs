defmodule BldgServer.BuildingsAuthorizationTest do
  @moduledoc """
  Coverage for the ownership/authorization gate that every mutating chat command
  and controller passes through: `Buildings.is_authorized_owner?/2` and its
  private `walk_up_owners/2` hierarchy walk.

  These assert *desired* behavior — a regression here is a privilege-escalation
  (or a lock-out), so they should hold through the protocol refactor.
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings

  @owner "owner@test.com"
  @stranger "stranger@test.com"

  describe "direct ownership" do
    test "an email listed in the bldg's owners is authorized" do
      b = bldg(%{owners: [@owner]})
      assert Buildings.is_authorized_owner?(@owner, b)
    end

    test "an email not listed is not authorized (no ancestors own it either)" do
      b = bldg(%{bldg_url: "g/solo", address: "g/solo", owners: [@owner]})
      refute Buildings.is_authorized_owner?(@stranger, b)
    end

    test "nil bldg is never authorized" do
      refute Buildings.is_authorized_owner?(@owner, nil)
    end

    test "nil email is never authorized" do
      b = bldg(%{owners: [@owner]})
      refute Buildings.is_authorized_owner?(nil, b)
    end

    test "empty / nil owners list denies everyone" do
      b_empty = bldg(%{owners: []})
      b_nil = bldg(%{owners: nil})
      refute Buildings.is_authorized_owner?(@owner, b_empty)
      refute Buildings.is_authorized_owner?(@owner, b_nil)
    end
  end

  describe "inherited ownership (walking up the container chain)" do
    test "owner of an ancestor bldg is authorized on a nested child, skipping floor segments" do
      # Ancestor owner bldg at g/team; its floor g/team/l0 is NOT a row in the
      # bldgs table (floors never are), and the child lives below that floor.
      bldg(%{bldg_url: "g/team", address: "g/team", name: "team", owners: [@owner]})
      child = bldg(%{bldg_url: "g/team/l0/b(1,1)", address: "g/team/l0/b(1,1)", name: "child", owners: []})

      assert Buildings.is_authorized_owner?(@owner, child)
    end

    test "a non-owner is denied even on a deeply nested child" do
      bldg(%{bldg_url: "g/team", address: "g/team", name: "team", owners: [@owner]})
      child = bldg(%{bldg_url: "g/team/l0/b(1,1)", address: "g/team/l0/b(1,1)", name: "child", owners: []})

      refute Buildings.is_authorized_owner?(@stranger, child)
    end

    test "a missing intermediate container is skipped but grants nothing unless a real ancestor owns it" do
      # No g/team bldg exists at all; the whole chain above the child is absent.
      # The walk must terminate at the root and deny, not crash or grant.
      child = bldg(%{bldg_url: "g/ghost/l0/b(1,1)", address: "g/ghost/l0/b(1,1)", name: "child", owners: []})

      refute Buildings.is_authorized_owner?(@owner, child)
    end
  end

  describe "termination / malformed input" do
    test "a bldg_url with no container segment terminates and denies (no infinite loop)" do
      b = bldg(%{bldg_url: "solo", address: "solo", owners: []})
      refute Buildings.is_authorized_owner?(@stranger, b)
    end

    test "a bldg directly on the ground floor terminates at \"g\"" do
      b = bldg(%{bldg_url: "g/b(1,1)", address: "g/b(1,1)", owners: []})
      refute Buildings.is_authorized_owner?(@stranger, b)
    end
  end

  describe "email normalization" do
    test "matching is case-insensitive" do
      b = bldg(%{owners: ["owner@test.com"]})
      assert Buildings.is_authorized_owner?("Owner@Test.com", b)
    end

    test "matching ignores surrounding whitespace on either side" do
      b = bldg(%{owners: ["  owner@test.com"]})
      assert Buildings.is_authorized_owner?("owner@test.com ", b)
    end

    test "normalization still distinguishes genuinely different emails" do
      b = bldg(%{owners: ["owner@test.com"]})
      refute Buildings.is_authorized_owner?("someone-else@test.com", b)
    end
  end
end
