defmodule BldgServerWeb.BldgCommandExecutorMoreTest do
  @moduledoc """
  Coverage for command-executor surfaces beyond `/edit`: `fetch_data/1` protocol
  handling, the `/connect` color/class kwarg parser (order-independent), the
  `/demote` not-promoted guard, and the `handle_info` crash isolation.
  """
  use BldgServer.DataCase

  alias BldgServerWeb.BldgCommandExecutor
  alias BldgServer.Relations

  describe "fetch_data/1" do
    test "empty url returns empty string" do
      assert BldgCommandExecutor.fetch_data("") == ""
    end

    test "unknown protocol raises" do
      assert_raise RuntimeError, ~r/Unknown protocol/, fn ->
        BldgCommandExecutor.fetch_data("ftp://example.com/x")
      end
    end

    test "http(s) protocol is explicitly not implemented" do
      assert_raise RuntimeError, ~r/not implemented/, fn ->
        BldgCommandExecutor.fetch_data("http://example.com/x")
      end
    end

    test "reads a value over redis://" do
      key = "bldg_test_fetch_#{System.unique_integer([:positive])}"
      {:ok, _} = Redix.command(:redix, ["SET", key, "hello-data"])
      on_exit(fn -> Redix.command(:redix, ["DEL", key]) end)

      assert BldgCommandExecutor.fetch_data("redis://#{key}") == "hello-data"
    end
  end

  describe "/connect color/class parsing" do
    setup do
      owner = "owner@test.com"
      bldg(%{bldg_url: "g/team", address: "g/team", name: "team", owners: [owner]})
      bldg(%{bldg_url: "g/team/l0/a", address: "g/team/l0/b(1,1)", flr: "g/team/l0", name: "a"})
      bldg(%{bldg_url: "g/team/l0/b", address: "g/team/l0/b(2,2)", flr: "g/team/l0", name: "b"})

      msg = %{
        "say_flr" => "g/team/l0",
        "say_flr_url" => "g/team/l0",
        "resident_email" => owner
      }

      %{msg: msg}
    end

    test "parses `with color X and class Y`", %{msg: msg} do
      {:ok, road} =
        BldgCommandExecutor.execute_command(
          ["/connect", "between", "a", "and", "b", "with", "color", "red", "and", "class", "lane"],
          msg
        )

      assert road.color == "red"
      assert road.road_class == "lane"
    end

    test "parses the reverse order `with class Y and color X`", %{msg: msg} do
      {:ok, road} =
        BldgCommandExecutor.execute_command(
          ["/connect", "between", "a", "and", "b", "with", "class", "highway", "and", "color", "blue"],
          msg
        )

      assert road.color == "blue"
      assert road.road_class == "highway"
    end

    test "a bare connect defaults class to \"road\" and leaves color nil", %{msg: msg} do
      {:ok, road} =
        BldgCommandExecutor.execute_command(["/connect", "between", "a", "and", "b"], msg)

      assert road.color == nil
      assert road.road_class == "road"
    end

    test "rejects a non-owner", %{msg: msg} do
      assert_raise RuntimeError, ~r/not authorized/, fn ->
        BldgCommandExecutor.execute_command(
          ["/connect", "between", "a", "and", "b"],
          %{msg | "resident_email" => "stranger@test.com"}
        )
      end

      assert Relations.list_roads() == []
    end
  end

  describe "/demote bldg inside" do
    test "raises a clear error when the bldg was never promoted (no matching picture-url key)" do
      bldg(%{bldg_url: "g/team", address: "g/team", name: "team", data: "{}"})
      bldg(%{bldg_url: "g/team/l0/thing", address: "g/team/l0/b(1,1)", flr: "g/team/l0", name: "thing", picture_url: "http://pic/thing.png"})

      assert_raise RuntimeError, ~r/not promoted/, fn ->
        BldgCommandExecutor.execute_command(
          ["/demote", "bldg", "thing", "inside"],
          %{"say_flr_url" => "g/team/l0"}
        )
      end
    end
  end

  describe "/create bldg parsing & flr derivation" do
    setup do
      owner = "owner@test.com"
      seed_ground_floor()
      # Container whose bldg_url is a name-alias ("g/team") but whose real
      # address is coordinate-based ("g/b(5,5)").
      bldg(%{bldg_url: "g/team", address: "g/b(5,5)", flr: "g", name: "team", owners: [owner]})

      msg = %{
        "say_flr_url" => "g/team/l0",
        "say_location" => "g/team/l0/b(10,10)",
        "resident_email" => owner
      }

      %{msg: msg, owner: owner}
    end

    test "derives the child flr from the container's address, not its bldg_url", %{msg: msg, owner: owner} do
      {:ok, child} =
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "mytask"],
          msg
        )

      # flr is "<container.address>/l0" = "g/b(5,5)/l0", NOT "g/team/l0".
      assert child.flr == "g/b(5,5)/l0"
      assert child.name == "mytask"
      assert child.entity_type == "task"
      assert owner in child.owners
    end

    test "summary greedily joins multiple words and stops at the next keyword", %{msg: msg} do
      {:ok, child} =
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "t", "summary", "quite", "a", "long", "one", "state", "Todo"],
          msg
        )

      assert child.summary == "quite a long one"
      assert child.state == "Todo"
    end

    test "parses width and height into the bldg footprint", %{msg: msg} do
      {:ok, child} =
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "t", "width", "3", "height", "2"],
          msg
        )

      assert child.width == 3
      assert child.height == 2
    end

    test "defaults to a 1x1 footprint when dimensions are omitted, and a non-integer is ignored", %{msg: msg} do
      {:ok, child} =
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "t", "width", "wide"],
          msg
        )

      assert child.width == 1
      assert child.height == 1
    end

    test "summary stops at the width keyword rather than swallowing it", %{msg: msg} do
      {:ok, child} =
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "t", "summary", "a", "tall", "one", "height", "4"],
          msg
        )

      assert child.summary == "a tall one"
      assert child.height == 4
    end

    test "rejects a non-owner", %{msg: msg} do
      assert_raise RuntimeError, ~r/not authorized/, fn ->
        BldgCommandExecutor.execute_command(
          ["/create", "task", "bldg", "with", "name", "t"],
          %{msg | "resident_email" => "stranger@test.com"}
        )
      end
    end
  end

  describe "handle_info crash isolation" do
    test "a command that raises does not crash the process (returns {:noreply, state})" do
      # "/edit" on a missing bldg raises; handle_info must rescue and continue.
      msg = %{
        "say_text" => "/edit ghost-bldg state Done",
        "resident_email" => "owner@test.com"
      }

      assert {:noreply, %{}} =
               BldgCommandExecutor.handle_info(%{event: "new_message", payload: msg}, %{})
    end
  end
end
