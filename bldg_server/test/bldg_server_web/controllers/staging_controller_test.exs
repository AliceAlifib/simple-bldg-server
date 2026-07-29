defmodule BldgServerWeb.StagingControllerTest do
  @moduledoc """
  Coverage for the staging/DGraph surface (previously entirely untested). DGraph
  is faked with a small Plug.Cowboy server (`:dgraph_url` points at it), so the
  controller's request-building, validation, and response translation are
  exercised without a real DGraph. (Bypass can't be used here — it pins ranch
  ~> 1.3, which conflicts with the ranch 2.x cowboy 2.14 requires.)
  """
  use BldgServerWeb.ConnCase, async: false

  @port 4568
  @ref __MODULE__.FakeDgraph

  defmodule FakeDgraph do
    @moduledoc "Fake DGraph HTTP endpoint: forwards each request to the test pid and replies with a canned response stored in an Agent (keyed by request path)."
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      send(opts[:test_pid], {:dgraph_request, conn.request_path, body})

      {status, resp_body} =
        Agent.get(opts[:agent], fn m -> Map.get(m, conn.request_path, {200, "{}"}) end)

      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(status, resp_body)
    end
  end

  setup %{conn: conn} do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    {:ok, _} = Plug.Cowboy.http(FakeDgraph, [test_pid: self(), agent: agent], port: @port, ref: @ref)

    prev = Application.get_env(:bldg_server, :dgraph_url)
    Application.put_env(:bldg_server, :dgraph_url, "http://127.0.0.1:#{@port}")

    on_exit(fn ->
      Plug.Cowboy.shutdown(@ref)
      Application.put_env(:bldg_server, :dgraph_url, prev)
    end)

    stub = fn path, status, body -> Agent.update(agent, &Map.put(&1, path, {status, body})) end
    {:ok, conn: put_req_header(conn, "accept", "application/json"), stub: stub}
  end

  describe "POST /v1/staging/data (write_data)" do
    test "enriches items with dgraph.type, mutates, and returns created uids", %{conn: conn, stub: stub} do
      stub.("/mutate", 200, ~s({"data":{"uids":{"a":"0x1","b":"0x2"}}}))

      body = %{
        "storage_type" => "dgraph",
        "namespace" => "myns",
        "entity_type" => "widget",
        "items" => [%{"name" => "a"}, %{"name" => "b"}]
      }

      conn = post(conn, "/v1/staging/data", body)

      resp = json_response(conn, 201)
      assert resp["success"] == true
      assert resp["count"] == 2
      assert Enum.sort(resp["keys"]) == ["0x1", "0x2"]

      # The controller wraps items under "set" and stamps dgraph.type on each.
      assert_received {:dgraph_request, "/mutate", req_body}
      decoded = Jason.decode!(req_body)
      assert [%{"name" => "a", "dgraph.type" => "widget"} | _] = decoded["set"]
    end

    test "rejects an empty items array with 400 before calling DGraph", %{conn: conn} do
      body = %{"storage_type" => "dgraph", "namespace" => "myns", "entity_type" => "widget", "items" => []}
      conn = post(conn, "/v1/staging/data", body)

      resp = json_response(conn, 400)
      assert resp["success"] == false
      assert resp["error"] =~ "Empty objects array"
      refute_received {:dgraph_request, _, _}
    end

    test "translates a DGraph error into 422", %{conn: conn, stub: stub} do
      stub.("/mutate", 500, "boom")

      body = %{
        "storage_type" => "dgraph",
        "namespace" => "myns",
        "entity_type" => "widget",
        "items" => [%{"name" => "a"}]
      }

      conn = post(conn, "/v1/staging/data", body)
      resp = json_response(conn, 422)
      assert resp["success"] == false
      assert resp["error"] =~ "Dgraph server error (500)"
    end
  end

  describe "reads" do
    test "GET /v1/staging/data/:namespace returns query data", %{conn: conn, stub: stub} do
      stub.("/query", 200, ~s({"data":{"all":[{"uid":"0x1","name":"a"}]}}))

      conn = get(conn, "/v1/staging/data/myns")
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["data"] == %{"all" => [%{"uid" => "0x1", "name" => "a"}]}

      # The namespace is passed as a bound DQL variable ($ns), not interpolated,
      # so an attacker-controlled value can't break out of the query string.
      assert_received {:dgraph_request, "/query", body}
      decoded = Jason.decode!(body)
      assert decoded["query"] =~ "eq(ns, $ns)"
      assert decoded["variables"] == %{"$ns" => "myns"}
    end

    test "POST /v1/staging/query passes the raw DQL through", %{conn: conn, stub: stub} do
      stub.("/query", 200, ~s({"data":{"all":[]}}))

      conn = post(conn, "/v1/staging/query", %{"query" => "{ all(func: eq(ns, \"x\")) { uid } }"})
      assert json_response(conn, 200)["success"] == true

      assert_received {:dgraph_request, "/query", dql}
      assert dql =~ "func: eq(ns"
    end
  end
end
