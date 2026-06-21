defmodule BldgServer.ProtocolGapsTest do
  @moduledoc """
  Executable documentation of two gaps the upcoming protocol work will close:

    1. Relocating a *container* bldg does not rewrite its nested children — their
       address/flr/bldg_url go stale (only connected roads are cascaded today).
    2. Bldgs have no footprint (only a point {x,y}), so overlap cannot be
       expressed and placement only avoids exact-coordinate collisions.

  Each gap has a GREEN characterization test (pins today's behavior — it will
  start failing the moment the feature lands, which is the signal to update it)
  and a `@tag :skip` SPEC test describing the target behavior (unskip when built).
  """
  use BldgServer.DataCase

  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg
  alias BldgServer.Repo

  # ── Gap 1: container relocation leaves children stale ──────────────────────

  describe "container relocation (gap)" do
    setup do
      seed_ground_floor()
      container = bldg(%{address: "g/b(5,5)", bldg_url: "g/b(5,5)", flr: "g", name: "team"})

      child =
        bldg(%{
          address: "g/b(5,5)/l0/b(1,1)",
          bldg_url: "g/b(5,5)/l0/b(1,1)",
          flr: "g/b(5,5)/l0",
          name: "child"
        })

      grandchild =
        bldg(%{
          address: "g/b(5,5)/l0/b(1,1)/l0/b(2,2)",
          bldg_url: "g/b(5,5)/l0/b(1,1)/l0/b(2,2)",
          flr: "g/b(5,5)/l0/b(1,1)/l0",
          name: "grandchild"
        })

      %{container: container, child: child, grandchild: grandchild}
    end

    test "TODAY: relocating the container leaves descendant addresses stale", ctx do
      assert {:ok, _moved} =
               Buildings.update_bldg(ctx.container, %{
                 "address" => "g/b(9,9)",
                 "bldg_url" => "g/b(9,9)"
               })

      # The container moved, but its descendants still point at the old subtree —
      # they are now orphaned. This is the gap the relocation feature must fix.
      assert Repo.get(Bldg, ctx.child.id).address == "g/b(5,5)/l0/b(1,1)"
      assert Repo.get(Bldg, ctx.child.id).flr == "g/b(5,5)/l0"
      assert Repo.get(Bldg, ctx.grandchild.id).address == "g/b(5,5)/l0/b(1,1)/l0/b(2,2)"
    end

    @tag skip: "pending: container relocation cascade — unskip when implemented"
    test "TARGET: relocating the container rewrites every descendant's address/flr/bldg_url", ctx do
      assert {:ok, _moved} =
               Buildings.update_bldg(ctx.container, %{
                 "address" => "g/b(9,9)",
                 "bldg_url" => "g/b(9,9)"
               })

      child = Repo.get(Bldg, ctx.child.id)
      assert child.address == "g/b(9,9)/l0/b(1,1)"
      assert child.flr == "g/b(9,9)/l0"
      assert child.bldg_url == "g/b(9,9)/l0/b(1,1)"

      grandchild = Repo.get(Bldg, ctx.grandchild.id)
      assert grandchild.address == "g/b(9,9)/l0/b(1,1)/l0/b(2,2)"
      assert grandchild.flr == "g/b(9,9)/l0/b(1,1)/l0"
    end
  end

  # ── Gap 2: bldgs are dimensionless points; overlap is unrepresentable ───────

  describe "bldg footprint / overlap (gap)" do
    test "TODAY: the schema models a single point, with no width/height footprint" do
      fields = Bldg.__schema__(:fields)
      assert :x in fields and :y in fields
      refute :width in fields
      refute :height in fields
    end

    test "TODAY: placement packs bldgs into adjacent cells (a 1x1, overlap-blind model)" do
      # {1,1} and {2,1} occupied -> the next slot is the immediately-adjacent
      # {3,1}. If these bldgs had any footprint > 1, they would overlap; the
      # placement layer has no way to know.
      assert Buildings.get_next_available_location([{1, 1}, {2, 1}], {1, 1}, 16, 12) == {3, 1}
    end

    @tag skip: "pending: bldg dimensions — unskip when width/height are added"
    test "TARGET: a bldg persists its width/height footprint" do
      b = bldg(%{address: "g/b(1,1)", bldg_url: "g/b(1,1)", width: 3, height: 2})
      reloaded = Repo.get(Bldg, b.id)
      assert reloaded.width == 3
      assert reloaded.height == 2
    end

    @tag skip: "pending: overlap avoidance — unskip when footprint placement lands"
    test "TARGET: a footprint is placed clear of existing footprints (no overlap)" do
      # A 3x3 at origin {1,1} covers x:1..3, y:1..3. A second 3x3 must not be
      # placed where its footprint intersects the first.
      occupied_footprints = [%{x: 1, y: 1, width: 3, height: 3}]
      placed = Buildings.find_free_footprint(occupied_footprints, 3, 3, 16, 12)
      refute rectangles_overlap?(placed, %{x: 1, y: 1, width: 3, height: 3})
    end

    defp rectangles_overlap?(a, b) do
      a.x < b.x + b.width and b.x < a.x + a.width and
        a.y < b.y + b.height and b.y < a.y + a.height
    end
  end
end
