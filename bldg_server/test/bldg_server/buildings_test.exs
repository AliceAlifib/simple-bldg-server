defmodule BldgServer.BuildingsTest do
  use BldgServer.DataCase

  alias BldgServer.Buildings

  describe "bldgs" do
    alias BldgServer.Buildings.Bldg

    @addr "g/b(1,2)/l0"
    @valid_attrs %{address: @addr, bldg_url: @addr, flr_level: 0, nesting_depth: 1, category: "some category", data: "some data", entity_type: "some entity_type", flr: "some flr", is_composite: true, name: "some name", picture_url: "some picture_url", state: "some state", summary: "some summary", tags: [], web_url: "some web_url", x: 42, y: 42}
    @update_attrs %{address: "some updated address", category: "some updated category", data: "some updated data", entity_type: "some updated entity_type", flr: "some updated flr", is_composite: false, name: "some updated name", picture_url: "some updated picture_url", state: "some updated state", summary: "some updated summary", tags: [], web_url: "some updated web_url", x: 43, y: 43}
    @invalid_attrs %{address: nil, category: nil, data: nil, entity_type: nil, flr: nil, is_composite: nil, name: nil, picture_url: nil, state: nil, summary: nil, tags: nil, web_url: nil, x: nil, y: nil}

    def bldg_fixture(attrs \\ %{}) do
      {:ok, bldg} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Buildings.create_bldg()

      bldg
    end

    test "list_bldgs/0 returns all bldgs" do
      bldg = bldg_fixture()
      assert Buildings.list_bldgs() == [bldg]
    end

    test "get_bldg!/1 returns the bldg with given id" do
      bldg = bldg_fixture()
      assert Buildings.get_bldg!(bldg.address) == bldg
    end

    test "create_bldg/1 with valid data creates a bldg" do
      assert {:ok, %Bldg{} = bldg} = Buildings.create_bldg(@valid_attrs)
      assert bldg.address == @addr
      assert bldg.category == "some category"
      assert bldg.data == "some data"
      assert bldg.entity_type == "some entity_type"
      assert bldg.flr == "some flr"
      assert bldg.is_composite == true
      assert bldg.name == "some name"
      assert bldg.picture_url == "some picture_url"
      assert bldg.state == "some state"
      assert bldg.summary == "some summary"
      assert bldg.tags == []
      assert bldg.web_url == "some web_url"
      assert bldg.x == 42
      assert bldg.y == 42
    end

    test "create_bldg/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Buildings.create_bldg(@invalid_attrs)
    end

    test "update_bldg/2 with valid data updates the bldg" do
      bldg = bldg_fixture()
      assert {:ok, %Bldg{} = bldg} = Buildings.update_bldg(bldg, @update_attrs)
      assert bldg.address == "some updated address"
      assert bldg.category == "some updated category"
      assert bldg.data == "some updated data"
      assert bldg.entity_type == "some updated entity_type"
      assert bldg.flr == "some updated flr"
      assert bldg.is_composite == false
      assert bldg.name == "some updated name"
      assert bldg.picture_url == "some updated picture_url"
      assert bldg.state == "some updated state"
      assert bldg.summary == "some updated summary"
      assert bldg.tags == []
      assert bldg.web_url == "some updated web_url"
      assert bldg.x == 43
      assert bldg.y == 43
    end

    test "update_bldg/2 with invalid data returns error changeset" do
      bldg = bldg_fixture()
      assert {:error, %Ecto.Changeset{}} = Buildings.update_bldg(bldg, @invalid_attrs)
      assert bldg == Buildings.get_bldg!(bldg.address)
    end

    test "delete_bldg/1 deletes the bldg" do
      bldg = bldg_fixture()
      assert {:ok, %Bldg{}} = Buildings.delete_bldg(bldg)
      assert_raise Ecto.NoResultsError, fn -> Buildings.get_bldg!(bldg.address) end
    end

    test "change_bldg/1 returns a bldg changeset" do
      bldg = bldg_fixture()
      assert %Ecto.Changeset{} = Buildings.change_bldg(bldg)
    end

    test "create_bldg/1 accepts color, size, and variant" do
      attrs = Map.merge(@valid_attrs, %{color: "red", size: "L", variant: "compact"})
      assert {:ok, %Bldg{} = bldg} = Buildings.create_bldg(attrs)
      assert bldg.color == "red"
      assert bldg.size == "L"
      assert bldg.variant == "compact"
    end

    test "changeset rejects an unknown size" do
      cs = Bldg.changeset(%Bldg{}, Map.put(@valid_attrs, :size, "XXXL"))
      refute cs.valid?
      assert %{size: [_ | _]} = errors_on(cs)
    end
  end
end
