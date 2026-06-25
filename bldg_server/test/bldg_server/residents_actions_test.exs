defmodule BldgServer.ResidentsActionsTest do
  @moduledoc """
  Coverage for resident action semantics: the `change_view_mode` direction
  invariant and `exit_bldg` coordinate derivation (including the asymmetric
  mixed-zero inputs).
  """
  use BldgServer.DataCase

  alias BldgServer.Residents

  describe "change_view_mode/2" do
    test "switching to bird_eye pins direction to 180" do
      r = resident(%{view_mode: "immersive", direction: 90})
      assert {:ok, updated} = Residents.change_view_mode(r, "bird_eye")
      assert updated.view_mode == "bird_eye"
      assert updated.direction == 180
    end

    test "switching to immersive sets the mode without forcing direction" do
      r = resident(%{view_mode: "bird_eye", direction: 180})
      assert {:ok, updated} = Residents.change_view_mode(r, "immersive")
      assert updated.view_mode == "immersive"
      assert updated.direction == 180
    end

    test "rejects an unknown view_mode" do
      r = resident(%{view_mode: "bird_eye"})
      assert {:error, changeset} = Residents.change_view_mode(r, "spaceship")
      assert %{view_mode: [_ | _]} = errors_on(changeset)
    end
  end

  describe "exit_bldg/5 coordinate derivation" do
    setup do
      %{resident: resident(%{location: "g/b(5,3)/l0/b(1,1)", flr: "g/b(5,3)/l0"})}
    end

    test "both-zero post-exit coords derive {bx, by+2} from the exited bldg", %{resident: r} do
      assert {:ok, updated} = Residents.exit_bldg(r, "g/b(5,3)", "g/some_url", 0, 0)
      assert {updated.x, updated.y} == {5, 5}
    end

    test "fully-specified non-zero coords are honored as-is", %{resident: r} do
      assert {:ok, updated} = Residents.exit_bldg(r, "g/b(5,3)", "g/some_url", 8, 9)
      assert {updated.x, updated.y} == {8, 9}
    end

    test "mixed input {0, 5} is honored as-is (only both-zero triggers the fallback)", %{resident: r} do
      assert {:ok, updated} = Residents.exit_bldg(r, "g/b(5,3)", "g/some_url", 0, 5)
      assert {updated.x, updated.y} == {0, 5}
    end

    test "mixed input {5, 0} is honored as-is", %{resident: r} do
      assert {:ok, updated} = Residents.exit_bldg(r, "g/b(5,3)", "g/some_url", 5, 0)
      assert {updated.x, updated.y} == {5, 0}
    end
  end
end
