defmodule BldgServerWeb.ResidentAuthTest do
  @moduledoc """
  Exercises the Tranche 2 auth: token validation, the dual-run flag, enforced
  401s on protected routes (incl. reads), and the resident-impersonation fix.
  """
  use BldgServerWeb.ConnCase

  alias BldgServer.{Residents, ResidentsAuth}
  alias BldgServerWeb.ResidentAuth

  setup %{conn: conn} do
    prev = Application.get_env(:bldg_server, :enforce_auth)
    on_exit(fn -> Application.put_env(:bldg_server, :enforce_auth, prev) end)
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp make_resident(email) do
    {:ok, resident} =
      Residents.create_resident(%{email: email, alias: email, name: email, home_bldg: "g"})

    resident
  end

  defp verified_session_token(resident) do
    sid = Ecto.UUID.generate()

    {:ok, _session} =
      ResidentsAuth.create_session(%{
        "session_id" => sid,
        "resident_id" => resident.id,
        "email" => resident.email,
        "status" => ResidentsAuth.verified(),
        "ip_address" => "127.0.0.1",
        "last_activity_time" => NaiveDateTime.utc_now()
      })

    {sid, BldgServer.Token.generate_auth_token(resident.id, sid)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "resident_from_token/1" do
    test "returns the resident for a valid token backed by a VERIFIED session" do
      resident = make_resident("valid@example.com")
      {_sid, token} = verified_session_token(resident)
      assert %{id: id} = ResidentAuth.resident_from_token(token)
      assert id == resident.id
    end

    test "returns nil when the session is REPLACED (revoked)" do
      resident = make_resident("revoked@example.com")
      {sid, token} = verified_session_token(resident)
      session = ResidentsAuth.get_session_by_session_id(sid)
      {:ok, _} = ResidentsAuth.update_session(session, %{status: ResidentsAuth.replaced()})
      assert ResidentAuth.resident_from_token(token) == nil
    end

    test "returns nil for a garbage / tampered token" do
      assert ResidentAuth.resident_from_token("not-a-real-token") == nil
      assert ResidentAuth.resident_from_token(nil) == nil
    end
  end

  describe "enforcement (enforce_auth = true)" do
    setup do
      Application.put_env(:bldg_server, :enforce_auth, true)
      :ok
    end

    test "a protected mutation without a token is rejected 401", %{conn: conn} do
      conn = post(conn, "/v1/bldgs", %{"bldg" => %{"name" => "x"}})
      assert json_response(conn, 401)["error"] =~ "authentication required"
    end

    test "a protected READ without a token is rejected 401", %{conn: conn} do
      conn = get(conn, "/v1/bldgs/scan/g")
      assert json_response(conn, 401)
    end

    test "a valid token passes the auth gate (reaches the controller)", %{conn: conn} do
      resident = make_resident("reader@example.com")
      {_sid, token} = verified_session_token(resident)
      # Not a 401 — the request is authenticated and reaches the action.
      conn = conn |> auth(token) |> get("/v1/residents/scan/g")
      assert conn.status != 401
    end
  end

  describe "dual-run (enforce_auth = false)" do
    setup do
      Application.put_env(:bldg_server, :enforce_auth, false)
      :ok
    end

    test "a protected read without a token still works (non-breaking)", %{conn: conn} do
      conn = get(conn, "/v1/residents/scan/g")
      assert conn.status == 200
    end
  end

  describe "trusted service (BLDG_SERVER_API_KEY)" do
    setup do
      prev_key = Application.get_env(:bldg_server, :service_api_key)
      Application.put_env(:bldg_server, :service_api_key, "test-service-key")
      on_exit(fn -> Application.put_env(:bldg_server, :service_api_key, prev_key) end)
      :ok
    end

    test "mint_token requires the service key (401 without it, even in dual-run)", %{conn: conn} do
      Application.put_env(:bldg_server, :enforce_auth, false)
      r = make_resident("mint-noauth@example.com")
      conn = post(conn, "/v1/residents/#{r.id}/token", %{})
      assert json_response(conn, 401)["error"] =~ "service authentication required"
    end

    test "mint_token with the service key returns a token that validates", %{conn: conn} do
      r = make_resident("mint-ok@example.com")

      conn =
        conn
        |> auth("test-service-key")
        |> post("/v1/residents/#{r.id}/token", %{})

      token = json_response(conn, 200)["token"]
      assert is_binary(token)
      assert ResidentAuth.resident_from_token(token).id == r.id
    end

    test "service key authorizes a protected mutation under enforcement", %{conn: conn} do
      Application.put_env(:bldg_server, :enforce_auth, true)
      # Without any credential this create would 401; with the service key it
      # passes the auth gate and reaches the controller.
      conn =
        conn
        |> auth("test-service-key")
        |> post("/v1/residents", %{"resident" => %{"email" => "svc@example.com"}})

      refute conn.status == 401
    end
  end

  describe "impersonation fix: act binds identity to the token, not the body" do
    test "with a token for A, act(resident_email: B) acts as A", %{conn: conn} do
      a = make_resident("a-actor@example.com")
      _b = make_resident("b-victim@example.com")
      {_sid, token} = verified_session_token(a)

      params = %{
        "resident_email" => "b-victim@example.com",
        "action_type" => "MOVE",
        "move_location" => "g/b(1,1)/l0/b(2,2)",
        "move_x" => 2,
        "move_y" => 2
      }

      conn = conn |> auth(token) |> post("/v1/residents/act", params)
      # The moved resident is A (the token owner), not B (the body email).
      assert json_response(conn, 200)["data"]["id"] == a.id
    end

    test "without a token (dual-run), the body email is used (legacy behavior)", %{conn: conn} do
      Application.put_env(:bldg_server, :enforce_auth, false)
      b = make_resident("b-legacy@example.com")

      params = %{
        "resident_email" => "b-legacy@example.com",
        "action_type" => "MOVE",
        "move_location" => "g/b(1,1)/l0/b(2,2)",
        "move_x" => 2,
        "move_y" => 2
      }

      conn = post(conn, "/v1/residents/act", params)
      assert json_response(conn, 200)["data"]["id"] == b.id
    end
  end
end
