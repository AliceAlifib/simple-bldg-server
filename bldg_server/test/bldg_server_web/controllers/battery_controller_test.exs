defmodule BldgServerWeb.BatteryControllerTest do
  use BldgServerWeb.ConnCase

  alias BldgServer.Batteries

  # The batteries resource excludes :create and its show/update/delete actions
  # are unreachable (route param is "bldg_address" but the actions match "id"),
  # so the real, client-facing battery API is the custom routes exercised here:
  # /batteries/{attach,detach,register,unregister}.

  @attach_attrs %{
    "battery_type" => "file-system-battery",
    "battery_vendor" => "acme",
    "battery_version" => "1",
    "bldg_url" => "g/b(1,1)/battery",
    "callback_url" => "http://localhost:9999/cb",
    "flr" => "g"
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all batteries", %{conn: conn} do
      conn = get(conn, Routes.battery_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "attach" do
    test "creates an attached battery and renders it", %{conn: conn} do
      conn = post(conn, "/v1/batteries/attach", battery: @attach_attrs)

      assert %{
               "id" => _id,
               "bldg_url" => "g/b(1,1)/battery",
               "callback_url" => "http://localhost:9999/cb",
               "flr" => "g",
               "is_attached" => true,
               "battery_type" => "file-system-battery"
             } = json_response(conn, 201)["data"]

      # The battery is persisted and marked attached for its bldg_url.
      assert %{is_attached: true} =
               Batteries.get_attached_battery_by_bldg_url("g/b(1,1)/battery")
    end

    test "renders errors when required fields are missing", %{conn: conn} do
      conn = post(conn, "/v1/batteries/attach", battery: %{"battery_type" => "x"})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "detach" do
    test "deletes the attached battery for a bldg_url", %{conn: conn} do
      battery(%{bldg_url: "g/b(2,2)/battery", is_attached: true})

      conn = post(conn, "/v1/batteries/detach", bldg_url: "g/b(2,2)/battery")
      assert response(conn, 204)

      assert Batteries.get_attached_battery_by_bldg_url("g/b(2,2)/battery") == nil
    end
  end

  describe "register / unregister (Redis pool)" do
    test "registers and unregisters a callback for a battery type", %{conn: conn} do
      type = "pool-type-#{System.unique_integer([:positive])}"
      cb = "http://localhost:9999/pool-cb"

      conn = post(conn, "/v1/batteries/register", battery: %{"battery_type" => type, "callback_url" => cb})
      assert json_response(conn, 200)["status"] == "registered"
      assert {:ok, callbacks} = Batteries.get_registered_callbacks(type)
      assert cb in callbacks

      conn = post(conn, "/v1/batteries/unregister", battery: %{"battery_type" => type, "callback_url" => cb})
      assert json_response(conn, 200)["status"] == "unregistered"
      assert {:ok, after_cbs} = Batteries.get_registered_callbacks(type)
      refute cb in after_cbs
    end

    test "register provisions an api_key when an owner_email is supplied", %{conn: conn} do
      type = "prov-type-#{System.unique_integer([:positive])}"

      conn =
        post(conn, "/v1/batteries/register",
          battery: %{
            "battery_type" => type,
            "callback_url" => "http://localhost:9999/prov-cb",
            "owner_email" => "owner@example.com"
          }
        )

      body = json_response(conn, 200)
      assert body["status"] == "registered"
      assert is_binary(body["api_key"])
      # the returned key authenticates back to a stored credential
      assert Batteries.authenticate_battery_key(body["api_key"]).battery_type == type
    end
  end

  describe "battery auth enforcement (enforce_auth = true)" do
    setup do
      prev = Application.get_env(:bldg_server, :enforce_auth)
      Application.put_env(:bldg_server, :enforce_auth, true)
      on_exit(fn -> Application.put_env(:bldg_server, :enforce_auth, prev) end)
      :ok
    end

    test "a battery route without a service key is rejected 401", %{conn: conn} do
      conn = post(conn, "/v1/batteries/attach", battery: @attach_attrs)
      assert json_response(conn, 401)["error"] =~ "battery authentication required"
    end

    test "a valid service key passes the battery auth gate", %{conn: conn} do
      {:ok, key, _cred} = Batteries.provision_battery_credential("file-system-battery", "o@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> key)
        |> post("/v1/batteries/attach", battery: @attach_attrs)

      # authenticated → reaches the action (created), not a 401
      assert conn.status != 401
    end
  end
end
