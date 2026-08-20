defmodule BldgServerWeb.MarkerControllerTest do
  use BldgServerWeb.ConnCase

  alias BldgServer.Relations
  alias BldgServer.Relations.Marker

  @create_attrs %{
    flr: "g/b(1,1)/l0",
    name: "spine",
    marker_type: "path",
    xs: [0, 5, 10],
    ys: [0, 0, 0],
    color: "blue",
    marker_class: "lane"
  }
  @update_attrs %{
    color: "red",
    marker_type: "area",
    xs: [0, 5, 5, 0],
    ys: [0, 0, 5, 5]
  }
  @invalid_attrs %{flr: nil, name: nil, marker_type: nil, xs: nil, ys: nil}

  def fixture(:marker) do
    {:ok, marker} = Relations.create_marker(@create_attrs)
    marker
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all markers", %{conn: conn} do
      conn = get(conn, Routes.marker_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create marker" do
    test "renders marker when data is valid", %{conn: conn} do
      conn = post(conn, Routes.marker_path(conn, :create), marker: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.marker_path(conn, :show, id))

      assert %{
               "id" => ^id,
               "flr" => "g/b(1,1)/l0",
               "name" => "spine",
               "marker_type" => "path",
               "xs" => [0, 5, 10],
               "ys" => [0, 0, 0],
               "color" => "blue",
               "marker_class" => "lane",
               "owners" => nil,
               "data" => nil
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.marker_path(conn, :create), marker: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "renders errors when an area has too few points", %{conn: conn} do
      attrs = %{@create_attrs | marker_type: "area", xs: [0, 1], ys: [0, 1]}
      conn = post(conn, Routes.marker_path(conn, :create), marker: attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update marker" do
    setup [:create_marker]

    test "renders marker when data is valid", %{conn: conn, marker: %Marker{id: id} = marker} do
      conn = put(conn, Routes.marker_path(conn, :update, marker), marker: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.marker_path(conn, :show, id))

      assert %{
               "id" => ^id,
               "color" => "red",
               "marker_type" => "area",
               "xs" => [0, 5, 5, 0],
               "ys" => [0, 0, 5, 5]
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, marker: marker} do
      conn = put(conn, Routes.marker_path(conn, :update, marker), marker: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete marker" do
    setup [:create_marker]

    test "deletes chosen marker", %{conn: conn, marker: marker} do
      conn = delete(conn, Routes.marker_path(conn, :delete, marker))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.marker_path(conn, :show, marker))
      end
    end
  end

  describe "look / scan" do
    test "look returns a bare array of the floor's direct markers only", %{conn: conn} do
      direct = marker(%{flr: "g/b(1,2)/l0", name: "direct"})
      marker(%{flr: "g/b(1,2)/l0/b(3,4)/l0", name: "nested"})
      marker(%{flr: "g/b(9,9)/l0", name: "other"})

      conn = get(conn, Routes.marker_path(conn, :look, URI.encode("g/b(1,2)/l0")))
      body = json_response(conn, 200)

      assert is_list(body)
      assert Enum.map(body, & &1["id"]) == [direct.id]
    end

    test "scan returns direct + nested markers, delimiter-safe", %{conn: conn} do
      direct = marker(%{flr: "g/b(1,2)/l1", name: "direct"})
      nested = marker(%{flr: "g/b(1,2)/l1/b(3,4)/l0", name: "nested"})
      marker(%{flr: "g/b(1,2)/l10", name: "l10-trap"})

      conn = get(conn, Routes.marker_path(conn, :scan, URI.encode("g/b(1,2)/l1")))
      body = json_response(conn, 200)

      assert is_list(body)
      assert Enum.map(body, & &1["id"]) |> Enum.sort() == Enum.sort([direct.id, nested.id])
    end
  end

  describe "delete_in_flr" do
    test "deletes every marker in the floor subtree and reports the count", %{conn: conn} do
      marker(%{flr: "g/b(1,2)/l0", name: "a"})
      marker(%{flr: "g/b(1,2)/l0/b(3,4)/l0", name: "b"})
      survivor = marker(%{flr: "g/b(1,2)/l10", name: "c"})

      conn = post(conn, Routes.marker_path(conn, :delete_in_flr), flr: "g/b(1,2)/l0")
      assert %{"deleted" => 2, "flr" => "g/b(1,2)/l0"} = json_response(conn, 200)

      assert Enum.map(Relations.list_markers(), & &1.id) == [survivor.id]
    end
  end

  defp create_marker(_) do
    marker = fixture(:marker)
    %{marker: marker}
  end
end
