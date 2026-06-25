defmodule BldgServerWeb.BatteryDispatchTest do
  @moduledoc """
  Unit coverage for the building blocks of BatteryChatDispatcher routing, kept
  deterministic (the full async broadcast path is covered by
  BatteryChatDispatcherTest). Pins:

    * `Buildings.get_batteries_in_floor/1` — the query the dispatcher uses to find
      battery bldgs on a floor (by flr_url + entity_type).
    * `Buildings.extract_battery_type/1`.
    * `BatteryChatDispatcher.send_message_to_battery/2` — actual webhook delivery.

  NOTE: there is a same-named `Batteries.get_batteries_in_floor/1` with different
  semantics (queries the Battery table filtered by `is_attached`). It currently
  has no callers — a refactor-trap namesake worth removing or renaming.
  """
  use BldgServer.DataCase, async: false

  alias BldgServer.Buildings
  alias BldgServerWeb.BatteryChatDispatcher

  describe "Buildings.get_batteries_in_floor/1" do
    test "returns only battery-type bldgs on the exact floor" do
      battery = bldg(%{flr_url: "g/team/l0", entity_type: "battery", name: "fsb", bldg_url: "g/team/l0/fsb", address: "g/team/l0/fsb"})
      _non_battery = bldg(%{flr_url: "g/team/l0", entity_type: "team", name: "t", bldg_url: "g/team/l0/t", address: "g/team/l0/b(1,1)"})
      _other_floor = bldg(%{flr_url: "g/other/l0", entity_type: "battery", name: "fsb2", bldg_url: "g/other/l0/fsb", address: "g/other/l0/fsb"})

      result = Buildings.get_batteries_in_floor("g/team/l0")
      assert Enum.map(result, & &1.bldg_url) == [battery.bldg_url]
    end
  end

  describe "Buildings.extract_battery_type/1" do
    test "uses the battery bldg's name as its type" do
      assert Buildings.extract_battery_type(%{entity_type: "battery", name: "file-system-battery"}) ==
               "file-system-battery"
    end
  end

  describe "send_message_to_battery/2" do
    defmodule Catcher do
      import Plug.Conn
      def init(opts), do: opts

      def call(conn, opts) do
        {:ok, body, conn} = read_body(conn)
        send(opts[:test_pid], {:battery_callback, Jason.decode!(body)})
        send_resp(conn, 200, ~s({"ok":true}))
      end
    end

    test "POSTs the message JSON to the given callback_url" do
      port = 4569
      ref = __MODULE__.CatcherRef
      {:ok, _} = Plug.Cowboy.http(Catcher, [test_pid: self()], port: port, ref: ref)
      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      msg = %{"say_text" => "/fsb watch /data", "say_flr_url" => "g/team/l0"}
      BatteryChatDispatcher.send_message_to_battery("http://127.0.0.1:#{port}/cb", msg)

      assert_receive {:battery_callback, payload}, 2_000
      assert payload["say_text"] == "/fsb watch /data"
      assert payload["say_flr_url"] == "g/team/l0"
    end
  end
end
