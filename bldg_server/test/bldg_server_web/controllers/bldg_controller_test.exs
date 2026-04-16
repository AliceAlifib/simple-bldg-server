defmodule BldgServerWeb.BldgControllerTest do
  use BldgServerWeb.ConnCase

  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg

  alias BldgServerWeb.BldgController


  @create_attrs %{
    address: "g/b(1,2)/l0",
    category: "some category",
    data: %{},
    entity_type: "some entity_type",
    flr: "some flr",
    is_composite: true,
    name: "some name",
    picture_url: "some picture_url",
    state: "some state",
    summary: "some summary",
    tags: [],
    web_url: "some web_url",
    x: 42,
    y: 42
  }
  @update_attrs %{
    address: "g/b(5,6)/l0",
    category: "some updated category",
    data: %{},
    entity_type: "some updated entity_type",
    flr: "some updated flr",
    is_composite: false,
    name: "some updated name",
    picture_url: "some updated picture_url",
    state: "some updated state",
    summary: "some updated summary",
    tags: [],
    web_url: "some updated web_url",
    x: 43,
    y: 43
  }
  @invalid_attrs %{address: nil, category: nil, data: nil, entity_type: nil, flr: nil, is_composite: nil, name: nil, picture_url: nil, state: nil, summary: nil, tags: nil, web_url: nil, x: nil, y: nil}

  def fixture(:bldg) do
    {:ok, bldg} = Buildings.create_bldg(@create_attrs)
    bldg
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all bldgs", %{conn: conn} do
      conn = get(conn, Routes.bldg_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create bldg" do
    test "renders bldg when data is valid", %{conn: conn} do
      conn = post(conn, Routes.bldg_path(conn, :create), bldg: @create_attrs)
      assert %{"address" => address} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.bldg_path(conn, :show, address))

      assert %{
               "id" => id,
               "address" => "g/b(1,2)/l0",
               "category" => "some category",
               "data" => %{},
               "entity_type" => "some entity_type",
               "flr" => "some flr",
               "is_composite" => true,
               "name" => "some name",
               "picture_url" => "some picture_url",
               "state" => "some state",
               "summary" => "some summary",
               "tags" => [],
               "web_url" => "some web_url",
               "x" => 42,
               "y" => 42
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.bldg_path(conn, :create), bldg: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update bldg" do
    setup [:create_bldg]

    test "renders bldg when data is valid", %{conn: conn, bldg: %Bldg{address: address} = bldg} do
      # TODO bldg_path doesn't return the right URL: it doesn't use the address instead of the id
      #conn = put(conn, Routes.bldg_path(conn, :update, bldg), bldg: @update_attrs)
      url = "/v1/bldgs/g/b(1,2)/l0"
      conn = put(conn, url, bldg: @update_attrs)
      assert %{"address" => "g/b(5,6)/l0"} = json_response(conn, 200)["data"]

      new_url = "/v1/bldgs/g/b(5,6)/l0"
      conn = get(conn, new_url)

      assert %{
               "id" => id,
               "address" => "g/b(5,6)/l0",
               "category" => "some updated category",
               "data" => %{},
               "entity_type" => "some updated entity_type",
               "flr" => "some updated flr",
               "is_composite" => false,
               "name" => "some updated name",
               "picture_url" => "some updated picture_url",
               "state" => "some updated state",
               "summary" => "some updated summary",
               "tags" => [],
               "web_url" => "some updated web_url",
               "x" => 43,
               "y" => 43
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, bldg: bldg} do
      # TODO bldg_path doesn't return the right URL: it doesn't use the address instead of the id
      #conn = put(conn, Routes.bldg_path(conn, :update, bldg), bldg: @invalid_attrs)
      url = "/v1/bldgs/g/b(1,2)/l0"
      conn = put(conn, url, bldg: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete bldg" do
    setup [:create_bldg]

    test "deletes chosen bldg", %{conn: conn, bldg: bldg} do
      # TODO bldg_path doesn't return the right URL: it doesn't use the address instead of the id
      #conn = delete(conn, Routes.bldg_path(conn, :delete, bldg))
      url = "/v1/bldgs/g/b(1,2)/l0"
      conn = delete(conn, url)
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.bldg_path(conn, :show, bldg))
      end
    end
  end

  describe "get minimal location" do
    
    test "returns min location" do
      locations = [{2,1}, {3,4}, {1,2}, {5,6}, {1,1}, {1,3}]
      result = BldgController.get_minimal_location(locations)
      assert result == {1,1}
    end

  end



  describe "get next available location" do

    test "returns next available location" do
      max_x = 16
      max_y = 12
      locations = [{2,1}, {3,4}, {3,1}, {5,6}, {4,1}]
      start_location = {2,1}
      result = BldgController.get_next_available_location(locations, start_location, max_x, max_y)
      assert {5,1} == result
    end

    test "returns next available location within row" do
      max_x = 16
      max_y = 12
      locations = [{1,1}, {2,1}, {4,1}]
      start_location = {1,1}
      result = BldgController.get_next_available_location(locations, start_location, max_x, max_y)
      assert {3,1} == result
    end

    test "returns next available location when assorted" do
      max_x = 16
      max_y = 12
      locations = [{10,11}, {9,11}]
      start_location = {9,11}
      result = BldgController.get_next_available_location(locations, start_location, max_x, max_y)
      assert {11,11} == result
    end

    test "returns place in next row if row is full" do
      max_x = 16
      max_y = 12
      locations = [{14,5}, {15,5}, {16,5}]
      start_location = {14,5}
      result = BldgController.get_next_available_location(locations, start_location, max_x, max_y)
      assert {14,6} == result
    end

  end


  defp create_bldg(_) do
    bldg = fixture(:bldg)
    {:ok, bldg: bldg}
  end

  describe "add_favorite_view_point" do
    setup [:create_bldg]

    test "appends a view-point and returns the updated list", %{conn: conn} do
      url = "/v1/bldgs/g/b(1,2)/l0/favorite_view_points"

      vp_a = %{
        "name" => "Front Door",
        "address" => "g/b(1,2)/l0",
        "direction" => 90.0,
        "size_delta" => 0,
        "camera_vertical_angle" => -10.0
      }

      conn = post(conn, url, view_point: vp_a)
      assert %{"favorite_view_points" => [returned_a]} = json_response(conn, 200)["data"]
      assert returned_a["name"] == "Front Door"
      assert returned_a["direction"] == 90.0
      assert returned_a["size_delta"] == 0

      vp_b = %{
        "name" => "Desk",
        "address" => "g/b(1,2)/l0",
        "direction" => -45.0,
        "size_delta" => 2,
        "camera_vertical_angle" => 5.0
      }

      conn = post(conn, url, view_point: vp_b)
      assert %{"favorite_view_points" => list} = json_response(conn, 200)["data"]
      assert length(list) == 2
      assert Enum.map(list, & &1["name"]) == ["Front Door", "Desk"]
    end
  end
end
