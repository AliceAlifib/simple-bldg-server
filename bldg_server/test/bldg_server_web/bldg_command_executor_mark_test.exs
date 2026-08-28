defmodule BldgServerWeb.BldgCommandExecutorMarkTest do
  @moduledoc """
  Coverage for the `/mark` chat command: `/mark path|area with name N and
  points (x,y) ... [and color C] [and class K]` — kwarg order independence,
  points parsing, defaults, upsert idempotency, validation and authorization.
  """
  use BldgServer.DataCase

  alias BldgServerWeb.BldgCommandExecutor
  alias BldgServer.Relations

  setup do
    owner = "owner@test.com"
    bldg(%{bldg_url: "g/team", address: "g/team", name: "team", owners: [owner]})

    msg = %{
      "say_flr" => "g/team/l0",
      "say_flr_url" => "g/team/l0",
      "resident_email" => owner
    }

    %{msg: msg}
  end

  # Tokenize exactly like handle_info does, so the tests exercise the real
  # grammar (space-split tokens).
  defp say(text, msg),
    do: text |> BldgCommandExecutor.parse_command() |> BldgCommandExecutor.execute_command(msg)

  describe "/mark path" do
    test "creates a path marker with parsed points, color and class", %{msg: msg} do
      {:ok, marker} =
        say(
          "/mark path with name spine and points (0,0) (5,0) (10,2) and color blue and class lane",
          msg
        )

      assert marker.flr == "g/team/l0"
      assert marker.name == "spine"
      assert marker.marker_type == "path"
      assert marker.xs == [0, 5, 10]
      assert marker.ys == [0, 0, 2]
      assert marker.color == "blue"
      assert marker.marker_class == "lane"
      assert marker.owners == ["owner@test.com"]
      assert Relations.find_marker("g/team/l0", "spine").id == marker.id
    end

    test "kwargs are order-independent", %{msg: msg} do
      {:ok, marker} =
        say(
          "/mark path with color red and class highway and points (1,1) (2,2) and name zig",
          msg
        )

      assert marker.name == "zig"
      assert marker.color == "red"
      assert marker.marker_class == "highway"
      assert marker.xs == [1, 2]
      assert marker.ys == [1, 2]
    end

    test "defaults class to \"road\" and color to nil", %{msg: msg} do
      {:ok, marker} = say("/mark path with name bare and points (0,0) (3,3)", msg)

      assert marker.marker_class == "road"
      assert marker.color == nil
    end

    test "accepts negative coordinates", %{msg: msg} do
      {:ok, marker} = say("/mark path with name neg and points (-3,-1) (0,0) (4,-2)", msg)

      assert marker.xs == [-3, 0, 4]
      assert marker.ys == [-1, 0, -2]
    end

    test "a repeat say is an upsert: one row, same id", %{msg: msg} do
      text = "/mark path with name spine and points (0,0) (5,0) and color blue"
      {:ok, first} = say(text, msg)
      {:ok, second} = say(text, msg)

      assert second.id == first.id
      assert length(Relations.list_markers()) == 1
    end

    test "a repeat say with changed geometry updates the existing row", %{msg: msg} do
      {:ok, first} = say("/mark path with name spine and points (0,0) (5,0)", msg)

      {:ok, second} =
        say("/mark path with name spine and points (0,0) (5,0) (9,9) and color green", msg)

      assert second.id == first.id
      assert second.xs == [0, 5, 9]
      assert second.color == "green"
      assert length(Relations.list_markers()) == 1
    end

    test "same name on another floor is a separate marker", %{msg: msg} do
      bldg(%{bldg_url: "g/other", address: "g/other", name: "other", owners: ["owner@test.com"]})
      {:ok, a} = say("/mark path with name spine and points (0,0) (5,0)", msg)

      {:ok, b} =
        say(
          "/mark path with name spine and points (0,0) (5,0)",
          %{msg | "say_flr" => "g/other/l0", "say_flr_url" => "g/other/l0"}
        )

      assert a.id != b.id
      assert length(Relations.list_markers()) == 2
    end

    test "raises a clear error when name is missing", %{msg: msg} do
      assert_raise RuntimeError, ~r/missing required `name`/, fn ->
        say("/mark path with points (0,0) (1,1)", msg)
      end

      assert Relations.list_markers() == []
    end

    test "raises a clear error with too few points", %{msg: msg} do
      assert_raise RuntimeError, ~r/at least 2 points/, fn ->
        say("/mark path with name lonely and points (0,0)", msg)
      end

      assert_raise RuntimeError, ~r/at least 2 points/, fn ->
        say("/mark path with name none", msg)
      end

      assert Relations.list_markers() == []
    end

    test "points stop at the first non-point token", %{msg: msg} do
      {:ok, marker} = say("/mark path with name p and points (0,0) (1,1) and color red", msg)
      assert marker.xs == [0, 1]
      assert marker.color == "red"
    end

    test "rejects a non-owner", %{msg: msg} do
      assert_raise RuntimeError, ~r/not authorized/, fn ->
        say(
          "/mark path with name spine and points (0,0) (5,0)",
          %{msg | "resident_email" => "stranger@test.com"}
        )
      end

      assert Relations.list_markers() == []
    end
  end

  describe "/mark area" do
    test "creates an area marker with 3+ points", %{msg: msg} do
      {:ok, marker} =
        say("/mark area with name zone and points (0,0) (4,0) (4,4) (0,4) and color yellow", msg)

      assert marker.marker_type == "area"
      assert marker.xs == [0, 4, 4, 0]
      assert marker.ys == [0, 0, 4, 4]
      assert marker.color == "yellow"
      assert marker.marker_class == "road"
    end

    test "requires at least 3 points", %{msg: msg} do
      assert_raise RuntimeError, ~r/at least 3 points/, fn ->
        say("/mark area with name thin and points (0,0) (4,4)", msg)
      end

      assert Relations.list_markers() == []
    end
  end

  describe "unknown /mark kind" do
    test "falls through to the unknown-command clause without raising", %{msg: msg} do
      # no clause matches `/mark circle`, so the catch-all "Ignoring unknown
      # command" clause handles it
      say("/mark circle with name c and points (0,0) (1,1)", msg)
      assert Relations.list_markers() == []
    end
  end
end
