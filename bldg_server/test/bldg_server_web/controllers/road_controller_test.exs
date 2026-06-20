defmodule BldgServerWeb.RoadControllerTest do
  use BldgServerWeb.ConnCase

  alias BldgServer.Relations
  alias BldgServer.Relations.Road

  @create_attrs %{
    flr: "some flr",
    from_address: "some from_address",
    to_address: "some to_address",
    from_x: 1,
    from_y: 1,
    to_x: 2,
    to_y: 2
  }
  @update_attrs %{
    flr: "some updated flr",
    from_address: "some updated from_address",
    to_address: "some updated to_address",
    from_x: 3,
    from_y: 3,
    to_x: 4,
    to_y: 4
  }
  @invalid_attrs %{flr: nil, from_address: nil, to_address: nil, from_x: nil, from_y: nil, to_x: nil, to_y: nil}

  def fixture(:road) do
    {:ok, road} = Relations.create_road(@create_attrs)
    road
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all roads", %{conn: conn} do
      conn = get(conn, Routes.road_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create road" do
    test "renders road when data is valid", %{conn: conn} do
      conn = post(conn, Routes.road_path(conn, :create), road: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.road_path(conn, :show, id))

      assert %{
               "id" => id,
               "flr" => "some flr",
               "from_address" => "some from_address",
               "to_address" => "some to_address"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.road_path(conn, :create), road: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update road" do
    setup [:create_road]

    test "renders road when data is valid", %{conn: conn, road: %Road{id: id} = road} do
      conn = put(conn, Routes.road_path(conn, :update, road), road: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.road_path(conn, :show, id))

      assert %{
               "id" => id,
               "flr" => "some updated flr",
               "from_address" => "some updated from_address",
               "to_address" => "some updated to_address"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, road: road} do
      conn = put(conn, Routes.road_path(conn, :update, road), road: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete road" do
    setup [:create_road]

    test "deletes chosen road", %{conn: conn, road: road} do
      conn = delete(conn, Routes.road_path(conn, :delete, road))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.road_path(conn, :show, road))
      end
    end
  end

  defp create_road(_) do
    road = fixture(:road)
    %{road: road}
  end
end
