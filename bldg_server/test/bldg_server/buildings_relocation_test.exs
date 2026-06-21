defmodule BldgServer.BuildingsRelocationTest do
  @moduledoc """
  Container relocation: moving a container bldg re-homes its entire nested
  subtree (built on Address.rebase/3). Covers the coord case, the name-aliased
  case where the address and bldg_url hierarchies move independently, and
  delimiter-safe isolation of sibling subtrees.
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg
  alias BldgServer.Relations.Road
  alias BldgServer.Repo

  setup do
    seed_ground_floor()
    :ok
  end

  test "relocating a container rewrites every descendant's address and flr" do
    container = bldg(%{address: "g/b(5,5)", bldg_url: "g/b(5,5)", flr: "g", name: "team"})

    child =
      bldg(%{
        address: "g/b(5,5)/l0/b(1,1)",
        bldg_url: "g/b(5,5)/l0/b(1,1)",
        flr: "g/b(5,5)/l0",
        flr_url: "g/b(5,5)/l0",
        name: "child"
      })

    grandchild =
      bldg(%{
        address: "g/b(5,5)/l0/b(1,1)/l0/b(2,2)",
        bldg_url: "g/b(5,5)/l0/b(1,1)/l0/b(2,2)",
        flr: "g/b(5,5)/l0/b(1,1)/l0",
        flr_url: "g/b(5,5)/l0/b(1,1)/l0",
        name: "grandchild"
      })

    assert {:ok, _} = Buildings.update_bldg(container, %{"address" => "g/b(9,9)", "bldg_url" => "g/b(9,9)"})

    child = Repo.get(Bldg, child.id)
    assert child.address == "g/b(9,9)/l0/b(1,1)"
    assert child.flr == "g/b(9,9)/l0"
    assert child.bldg_url == "g/b(9,9)/l0/b(1,1)"

    grandchild = Repo.get(Bldg, grandchild.id)
    assert grandchild.address == "g/b(9,9)/l0/b(1,1)/l0/b(2,2)"
    assert grandchild.flr == "g/b(9,9)/l0/b(1,1)/l0"
  end

  test "name-aliased container: address moves but the bldg_url alias stays, each rebased on its own root" do
    # bldg_url is a name alias ("g/team"); the real address is coordinate-based.
    container = bldg(%{address: "g/b(5,5)", bldg_url: "g/team", flr: "g", name: "team"})

    child =
      bldg(%{
        address: "g/b(5,5)/l0/b(1,1)",
        bldg_url: "g/team/l0/b(1,1)",
        flr: "g/b(5,5)/l0",
        flr_url: "g/team/l0",
        name: "child"
      })

    # Only the address (coords) moves; the alias stays "g/team".
    assert {:ok, _} = Buildings.update_bldg(container, %{"address" => "g/b(9,9)"})

    child = Repo.get(Bldg, child.id)
    assert child.address == "g/b(9,9)/l0/b(1,1)"
    assert child.flr == "g/b(9,9)/l0"
    # the bldg_url hierarchy did not move, so it is left intact
    assert child.bldg_url == "g/team/l0/b(1,1)"
    assert child.flr_url == "g/team/l0"
  end

  test "roads on descendant floors are rebased, with floor-local coords preserved" do
    container = bldg(%{address: "g/b(5,5)", bldg_url: "g/b(5,5)", flr: "g", name: "team"})
    bldg(%{address: "g/b(5,5)/l0/b(1,1)", bldg_url: "g/b(5,5)/l0/b(1,1)", flr: "g/b(5,5)/l0", name: "a"})
    bldg(%{address: "g/b(5,5)/l0/b(2,2)", bldg_url: "g/b(5,5)/l0/b(2,2)", flr: "g/b(5,5)/l0", name: "b"})

    road =
      road(%{
        flr: "g/b(5,5)/l0",
        from_address: "g/b(5,5)/l0/b(1,1)",
        from_x: 1,
        from_y: 1,
        to_address: "g/b(5,5)/l0/b(2,2)",
        to_x: 2,
        to_y: 2
      })

    assert {:ok, _} = Buildings.update_bldg(container, %{"address" => "g/b(9,9)", "bldg_url" => "g/b(9,9)"})

    road = Repo.get(Road, road.id)
    assert road.flr == "g/b(9,9)/l0"
    assert road.from_address == "g/b(9,9)/l0/b(1,1)"
    assert road.to_address == "g/b(9,9)/l0/b(2,2)"
    # endpoint coords are floor-local — unchanged by the move
    assert {road.from_x, road.from_y, road.to_x, road.to_y} == {1, 1, 2, 2}
  end

  test "a sibling subtree is not touched by the relocation" do
    moving = bldg(%{address: "g/b(5,5)", bldg_url: "g/b(5,5)", flr: "g", name: "moving"})
    bldg(%{address: "g/b(5,5)/l0/b(1,1)", bldg_url: "g/b(5,5)/l0/b(1,1)", flr: "g/b(5,5)/l0", name: "inner"})

    sibling_child =
      bldg(%{
        address: "g/b(7,7)/l0/b(1,1)",
        bldg_url: "g/b(7,7)/l0/b(1,1)",
        flr: "g/b(7,7)/l0",
        name: "sibling-child"
      })

    assert {:ok, _} = Buildings.update_bldg(moving, %{"address" => "g/b(9,9)", "bldg_url" => "g/b(9,9)"})

    # The sibling's nested child is on a different subtree and must be untouched.
    assert Repo.get(Bldg, sibling_child.id).address == "g/b(7,7)/l0/b(1,1)"
  end
end
