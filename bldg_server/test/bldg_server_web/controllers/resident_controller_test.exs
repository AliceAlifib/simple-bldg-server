defmodule BldgServerWeb.ResidentControllerTest do
  use BldgServerWeb.ConnCase
  use Bamboo.Test

  alias BldgServer.Residents
  alias BldgServer.Residents.Resident
  alias BldgServer.ResidentsAuth

  @create_attrs %{
    alias: "some alias",
    direction: 42,
    email: "some email",
    home_bldg: "some home_bldg",
    is_online: false,
    last_login_at: ~N[2010-04-17 14:00:00],
    location: "g/b(17,24)/l0/b(4,5)",
    flr: "g/b(17,24)/l0",
    name: "some name",
    other_attributes: %{},
    previous_messages: [],
    session_id: "7488a646-e31f-11e4-aace-600308960662"
  }
  @update_attrs %{
    alias: "some updated alias",
    direction: 43,
    email: "some updated email",
    home_bldg: "some updated home_bldg",
    is_online: true,
    last_login_at: ~N[2011-05-18 15:01:01],
    location: "g/b(17,24)/l0/b(6,8)",
    flr: "g/b(17,24)/l0",
    name: "some updated name",
    other_attributes: %{},
    previous_messages: [],
    session_id: "7488a646-e31f-11e4-aace-600308960668"
  }
  @invalid_attrs %{alias: nil, direction: nil, email: nil, home_bldg: nil, is_online: nil, last_login_at: nil, location: nil, name: nil, other_attributes: nil, previous_messages: nil, session_id: nil}

  def fixture(:resident) do
    {:ok, resident} = Residents.create_resident(@create_attrs)
    resident
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all residents", %{conn: conn} do
      conn = get(conn, Routes.resident_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create resident" do
    test "renders resident when data is valid", %{conn: conn} do
      conn = post(conn, Routes.resident_path(conn, :create), resident: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.resident_path(conn, :show, id))

      assert %{
               "id" => ^id,
               "alias" => "some alias",
               "direction" => 42,
               "email" => "some email",
               "home_bldg" => "some home_bldg",
               "is_online" => false,
               "last_login_at" => "2010-04-17T14:00:00",
               "location" => "g/b(17,24)/l0/b(4,5)",
               "flr" => "g/b(17,24)/l0",
               "name" => "some name",
               "other_attributes" => %{},
               "previous_messages" => [],
               "session_id" => "7488a646-e31f-11e4-aace-600308960662"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.resident_path(conn, :create), resident: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update resident" do
    setup [:create_resident]

    test "renders resident when data is valid", %{conn: conn, resident: %Resident{id: id} = resident} do
      conn = put(conn, Routes.resident_path(conn, :update, resident), resident: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.resident_path(conn, :show, id))

      assert %{
               "id" => ^id,
               "alias" => "some updated alias",
               "direction" => 43,
               "email" => "some updated email",
               "home_bldg" => "some updated home_bldg",
               "is_online" => true,
               "last_login_at" => "2011-05-18T15:01:01",
               "location" => "g/b(17,24)/l0/b(6,8)",
               "flr" => "g/b(17,24)/l0",
               "name" => "some updated name",
               "other_attributes" => %{},
               "previous_messages" => [],
               "session_id" => "7488a646-e31f-11e4-aace-600308960668"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, resident: resident} do
      conn = put(conn, Routes.resident_path(conn, :update, resident), resident: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "login resident" do
    setup [:create_resident]

    test "with no prior verified session, starts email verification and returns a pending partial resident",
         %{conn: conn} do
      conn = post(conn, "/v1/residents/login", email: "some email")

      # The pending response carries only the email and a fresh session_id;
      # the rest is nil until the magic link is verified.
      data = json_response(conn, 200)["data"]
      assert data["email"] == "some email"
      assert data["id"] == nil
      assert is_binary(data["session_id"])

      # A magic-link verification email was dispatched (captured by TestAdapter).
      assert_delivered_email_matches(%{to: [{_, "some email"}]})
    end

    test "with a recent verified session from the same ip, returns the full resident",
         %{conn: conn, resident: %Resident{id: id} = resident} do
      # Seed a VERIFIED session for this resident from the test conn's ip so the
      # login short-circuits to the :has_valid_session path.
      session(%{
        resident_id: id,
        email: resident.email,
        ip_address: "127.0.0.1",
        status: ResidentsAuth.verified()
      })

      conn = post(conn, "/v1/residents/login", email: "some email")
      data = json_response(conn, 200)["data"]
      assert data["id"] == id
      assert data["email"] == "some email"
      assert data["location"] == "g/b(17,24)/l0/b(4,5)"
    end
  end

  describe "resident act - move" do
    setup [:create_resident]

    test "resident moves when action data is valid", %{conn: conn, resident: %Resident{id: id} = resident} do
      conn = post(conn, "/v1/residents/act", %{"resident_email" => "some email", "action_type" => "MOVE", "move_location" => "g/b(17,24)/l0/b(10,15)", "move_x" => 10, "move_y" => 15})
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.resident_path(conn, :show, id))
      # NOTE: the previous version put `expected_last_login = DateTime.utc_now()`
      # in the pattern, which silently *bound* rather than asserted. MOVE doesn't
      # touch last_login_at, so we assert only the fields MOVE actually changes.
      assert %{
               "id" => ^id,
               "email" => "some email",
               "location" => "g/b(17,24)/l0/b(10,15)",
               "x" => 10,
               "y" => 15,
               "flr" => "g/b(17,24)/l0",
               "session_id" => "7488a646-e31f-11e4-aace-600308960662"
             } = json_response(conn, 200)["data"]
    end

  end


  describe "delete resident" do
    setup [:create_resident]

    test "deletes chosen resident", %{conn: conn, resident: resident} do
      conn = delete(conn, Routes.resident_path(conn, :delete, resident))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.resident_path(conn, :show, resident))
      end
    end
  end

  defp create_resident(_) do
    resident = fixture(:resident)
    {:ok, resident: resident}
  end
end
