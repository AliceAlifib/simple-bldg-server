defmodule BldgServer.BuildingsCascadeTest do
  @moduledoc """
  Coverage for the floor-membership query that drives recursive scan and the
  cascade delete. The query must be *delimiter-safe*: a floor `…/l1` must not
  also match the numerically-prefixed sibling floor `…/l10`. Getting this wrong
  silently sweeps unrelated bldgs into a scan — or, via delete_bldg_cascade, into
  deletion (data loss).
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings

  describe "list_all_bldgs_in_flr/1 delimiter safety" do
    test "a floor does not match a numerically-prefixed sibling floor (l1 vs l10)" do
      # Same parent, two floors differing only by a numeric suffix.
      on_l1 = bldg(%{flr: "g/b(1,2)/l1", address: "g/b(1,2)/l1/b(1,1)", bldg_url: "g/b(1,2)/l1/b(1,1)", name: "on-l1"})
      _on_l10 = bldg(%{flr: "g/b(1,2)/l10", address: "g/b(1,2)/l10/b(2,2)", bldg_url: "g/b(1,2)/l10/b(2,2)", name: "on-l10"})

      addresses = Buildings.list_all_bldgs_in_flr("g/b(1,2)/l1") |> Enum.map(& &1.address)

      assert on_l1.address in addresses
      refute "g/b(1,2)/l10/b(2,2)" in addresses
    end

    test "includes direct children (flr == floor) and nested descendants" do
      direct = bldg(%{flr: "g/b(1,2)/l0", address: "g/b(1,2)/l0/b(3,4)", bldg_url: "g/b(1,2)/l0/b(3,4)", name: "direct"})
      nested = bldg(%{flr: "g/b(1,2)/l0/b(3,4)/l0", address: "g/b(1,2)/l0/b(3,4)/l0/b(5,6)", bldg_url: "g/b(1,2)/l0/b(3,4)/l0/b(5,6)", name: "nested"})

      addresses = Buildings.list_all_bldgs_in_flr("g/b(1,2)/l0") |> Enum.map(& &1.address)

      assert direct.address in addresses
      assert nested.address in addresses
    end
  end

  describe "delete_bldg_cascade/1" do
    test "deletes the target and all nested descendants, leaving unrelated bldgs intact" do
      target = bldg(%{flr: "g", address: "g/b(1,2)", bldg_url: "g/b(1,2)", name: "target"})
      child = bldg(%{flr: "g/b(1,2)/l0", address: "g/b(1,2)/l0/b(1,1)", bldg_url: "g/b(1,2)/l0/b(1,1)", name: "child"})
      grandchild = bldg(%{flr: "g/b(1,2)/l0/b(1,1)/l0", address: "g/b(1,2)/l0/b(1,1)/l0/b(2,2)", bldg_url: "g/b(1,2)/l0/b(1,1)/l0/b(2,2)", name: "grandchild"})

      # A sibling on the ground floor and its own nested child — must survive.
      sibling = bldg(%{flr: "g", address: "g/b(3,4)", bldg_url: "g/b(3,4)", name: "sibling"})
      sibling_child = bldg(%{flr: "g/b(3,4)/l0", address: "g/b(3,4)/l0/b(1,1)", bldg_url: "g/b(3,4)/l0/b(1,1)", name: "sibling-child"})

      assert {:ok, _} = Buildings.delete_bldg_cascade(target)

      refute bldg_exists?(target.address)
      refute bldg_exists?(child.address)
      refute bldg_exists?(grandchild.address)

      assert bldg_exists?(sibling.address)
      assert bldg_exists?(sibling_child.address)
    end
  end

  defp bldg_exists?(address) do
    match?(%BldgServer.Buildings.Bldg{}, BldgServer.Repo.get_by(BldgServer.Buildings.Bldg, address: address))
  end
end
