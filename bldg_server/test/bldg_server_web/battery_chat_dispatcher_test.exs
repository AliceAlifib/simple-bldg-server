defmodule BldgServerWeb.BatteryChatDispatcherTest do
  @moduledoc """
  End-to-end check of the attach dispatch path: a chat message said on a floor
  that hosts an *attached* battery bldg must be delivered to that battery's own
  `callback_url` (the per-sprite file-system-battery model), not to a randomly
  chosen registered callback.

  Exercises the real `BatteryChatDispatcher` GenServer (running in the app
  supervision tree) + Finch, against a throwaway Plug.Cowboy HTTP catcher.
  """
  use BldgServer.DataCase, async: false

  alias BldgServer.Batteries
  alias BldgServer.Buildings.Bldg
  alias BldgServer.Repo

  @catcher_ref __MODULE__.Catcher

  defmodule Catcher do
    @moduledoc "Minimal HTTP endpoint that forwards each received body to a test pid."
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      send(opts[:test_pid], {:battery_callback, Jason.decode!(body)})
      send_resp(conn, 200, ~s({"ok":true}))
    end
  end

  setup do
    port = 4567
    {:ok, _} = Plug.Cowboy.http(Catcher, [test_pid: self()], port: port, ref: @catcher_ref)
    on_exit(fn -> Plug.Cowboy.shutdown(@catcher_ref) end)

    %{callback_url: "http://127.0.0.1:#{port}/cb"}
  end

  defp battery_bldg!(flr_url, bldg_url, name) do
    %Bldg{}
    |> Bldg.changeset(%{
      entity_type: "battery",
      name: name,
      bldg_url: bldg_url,
      flr_url: flr_url,
      address: bldg_url,
      x: 0,
      y: 0,
      is_composite: false,
      flr_level: 0,
      nesting_depth: 0
    })
    |> Repo.insert!()
  end

  test "routes a floor message to the attached battery's own callback_url", %{
    callback_url: callback_url
  } do
    flr_url = "g-attach-test"
    bldg_url = "g-attach-test/fsb"

    battery_bldg!(flr_url, bldg_url, "file-system-battery")

    {:ok, _battery} =
      Batteries.create_battery(%{
        is_attached: true,
        bldg_url: bldg_url,
        flr: flr_url,
        callback_url: callback_url,
        battery_type: "file-system-battery"
      })

    msg = %{
      "say_flr_url" => flr_url,
      "say_text" => "/file-system-battery watch /data/plan",
      "say_speaker" => "tester@example.com"
    }

    BldgServerWeb.Endpoint.broadcast!("chat", "new_message", msg)

    # The dispatcher is an app-tree singleton that serially processes every
    # "chat" broadcast (including those from other tests in a full-suite run),
    # so allow a generous window to avoid a rare order-dependent flake.
    assert_receive {:battery_callback, payload}, 5_000
    assert payload["say_text"] == "/file-system-battery watch /data/plan"
    assert payload["say_flr_url"] == flr_url
  end
end
