defmodule BldgServerWeb.FloorChannelTest do
  @moduledoc """
  Golden tests for the on-the-wire shape produced by FloorChannel — the protocol
  surface a refactor is most likely to break. The serializers are pinned
  field-by-field, and an end-to-end `request_scan` is exercised through a real
  joined socket.
  """
  use BldgServerWeb.ChannelCase

  alias BldgServerWeb.FloorChannel

  describe "serialize_bldg/1 (golden)" do
    test "emits exactly the documented key set, in parity with BldgView" do
      b =
        bldg(%{
          bldg_url: "g/b(1,2)",
          address: "g/b(1,2)",
          name: "thing",
          x: 1,
          y: 2,
          entity_type: "team",
          color: "red",
          size: "L",
          visual_language: %{"team" => "buildingWithStorefront"}
        })

      out = FloorChannel.serialize_bldg(b)

      expected_keys =
        ~w(id bldg_url address name flr flr_url flr_level nesting_depth x y
           is_composite web_url entity_type state category tags summary picture_url
           color size variant owners previous_messages updated_at data
           visual_language favorite_view_points)a
        |> Enum.sort()

      assert Map.keys(out) |> Enum.sort() == expected_keys
      assert out.bldg_url == "g/b(1,2)"
      assert out.color == "red"
      assert out.size == "L"
      # visual_language is JSON-encoded inline (a string, not a map)
      assert out.visual_language == Jason.encode!(%{"team" => "buildingWithStorefront"})
      # favorite_view_points defaults to [] (the parity fix)
      assert out.favorite_view_points == []
    end
  end

  describe "serialize_resident/1 and serialize_road/1 (golden)" do
    test "resident key set matches ResidentView" do
      r = resident(%{view_mode: "bird_eye", direction: 180})
      out = FloorChannel.serialize_resident(r)

      expected =
        ~w(id email alias name home_bldg is_online location flr flr_url x y direction
           previous_messages other_attributes nesting_depth session_id last_login_at
           updated_at view_mode)a
        |> Enum.sort()

      assert Map.keys(out) |> Enum.sort() == expected
      assert out.view_mode == "bird_eye"
    end

    test "road key set matches RoadView" do
      rd = road(%{color: "blue", road_class: "lane"})
      out = FloorChannel.serialize_road(rd)

      expected =
        ~w(id flr from_address to_address from_x from_y to_x to_y owners color road_class)a
        |> Enum.sort()

      assert Map.keys(out) |> Enum.sort() == expected
      assert out.color == "blue"
      assert out.road_class == "lane"
    end
  end

  describe "request_scan end-to-end" do
    test "pushes scan_result with the container, nested bldgs, residents and roads" do
      # Container floor "g/b(1,2)/l0" and its contents.
      bldg(%{bldg_url: "g/b(1,2)", address: "g/b(1,2)", name: "container"})
      child = bldg(%{bldg_url: "g/b(1,2)/l0/b(3,4)", address: "g/b(1,2)/l0/b(3,4)", flr: "g/b(1,2)/l0", name: "child"})
      resident(%{flr: "g/b(1,2)/l0", location: "g/b(1,2)/l0/b(5,6)"})
      road(%{flr: "g/b(1,2)/l0"})

      {:ok, _, socket} =
        BldgServerWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(FloorChannel, "floor:g/b(1,2)/l0")

      push(socket, "request_scan", %{})

      assert_push "scan_result", payload
      addresses = Enum.map(payload.bldgs, & &1.address)
      # container is prepended, child is included
      assert "g/b(1,2)" in addresses
      assert child.address in addresses
      assert length(payload.residents) == 1
      assert length(payload.roads) == 1
    end
  end
end
