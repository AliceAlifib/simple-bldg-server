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
           width height is_composite web_url entity_type state category tags summary
           picture_url color size variant owners previous_messages updated_at data
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

  describe "serialize_resident_public/1 and serialize_road/1 (golden)" do
    test "public resident key set omits email and session_id" do
      r = resident(%{view_mode: "bird_eye", direction: 180})
      out = FloorChannel.serialize_resident_public(r)

      # DELIBERATELY excludes email and session_id: the floor channel is
      # world-readable, so neither PII nor the session credential may be
      # broadcast. See FloorChannel.serialize_resident_public/1.
      expected =
        ~w(id alias name home_bldg is_online location flr flr_url x y direction
           previous_messages other_attributes nesting_depth last_login_at
           updated_at view_mode)a
        |> Enum.sort()

      assert Map.keys(out) |> Enum.sort() == expected
      refute Map.has_key?(out, :email)
      refute Map.has_key?(out, :session_id)
      assert out.view_mode == "bird_eye"
    end

    test "road key set matches RoadView" do
      rd = road(%{color: "blue", road_class: "lane"})
      out = FloorChannel.serialize_road(rd)

      expected =
        ~w(id flr from_address to_address from_x from_y to_x to_y owners color road_class curve)a
        |> Enum.sort()

      assert Map.keys(out) |> Enum.sort() == expected
      assert out.color == "blue"
      assert out.road_class == "lane"
    end
  end

  describe "UserSocket authentication" do
    setup do
      prev = Application.get_env(:bldg_server, :enforce_auth)
      on_exit(fn -> Application.put_env(:bldg_server, :enforce_auth, prev) end)
      :ok
    end

    defp verified_token do
      r = resident(%{})
      sid = Ecto.UUID.generate()

      {:ok, _session} =
        BldgServer.ResidentsAuth.create_session(%{
          "session_id" => sid,
          "resident_id" => r.id,
          "email" => r.email,
          "status" => BldgServer.ResidentsAuth.verified(),
          "ip_address" => "127.0.0.1",
          "last_activity_time" => NaiveDateTime.utc_now()
        })

      {BldgServer.Token.generate_auth_token(r.id, sid), r}
    end

    test "enforcing: connect without a token is denied" do
      Application.put_env(:bldg_server, :enforce_auth, true)
      assert :error = connect(BldgServerWeb.UserSocket, %{})
    end

    test "enforcing: connect with a valid token assigns the resident" do
      Application.put_env(:bldg_server, :enforce_auth, true)
      {token, r} = verified_token()
      assert {:ok, socket} = connect(BldgServerWeb.UserSocket, %{"token" => token})
      assert socket.assigns.current_resident.id == r.id
    end

    test "dual-run: connect without a token is accepted as anonymous" do
      Application.put_env(:bldg_server, :enforce_auth, false)
      assert {:ok, socket} = connect(BldgServerWeb.UserSocket, %{})
      assert socket.assigns.current_resident == nil
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
