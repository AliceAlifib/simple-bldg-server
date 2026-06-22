defmodule BldgServer.BatteriesTest do
  use BldgServer.DataCase

  alias BldgServer.Batteries

  describe "batteries" do
    alias BldgServer.Batteries.Battery

    @valid_attrs %{battery_type: "some battery_type", battery_vendor: "some battery_vendor", battery_version: "some battery_version", bldg_url: "some bldg_url", callback_url: "some callback_url", direct_only: true, flr: "some flr", is_attached: true}
    @update_attrs %{battery_type: "some updated battery_type", battery_vendor: "some updated battery_vendor", battery_version: "some updated battery_version", bldg_url: "some updated bldg_url", callback_url: "some updated callback_url", direct_only: false, flr: "some updated flr", is_attached: false}
    @invalid_attrs %{battery_type: nil, battery_vendor: nil, battery_version: nil, bldg_url: nil, callback_url: nil, direct_only: nil, flr: nil, is_attached: nil}

    def battery_fixture(attrs \\ %{}) do
      {:ok, battery} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Batteries.create_battery()

      battery
    end

    test "list_batteries/0 returns all batteries" do
      battery = battery_fixture()
      assert Batteries.list_batteries() == [battery]
    end

    test "get_battery!/1 returns the battery with given id" do
      battery = battery_fixture()
      assert Batteries.get_battery!(battery.id) == battery
    end

    test "get_attached_battery_by_bldg_url/1 returns the attached battery for a bldg" do
      battery = battery_fixture(%{bldg_url: "g/home/battery", is_attached: true})
      assert Batteries.get_attached_battery_by_bldg_url("g/home/battery") == battery
    end

    test "get_attached_battery_by_bldg_url/1 returns nil when no battery is attached" do
      assert Batteries.get_attached_battery_by_bldg_url("g/home/nope") == nil
    end

    test "get_attached_battery_by_bldg_url/1 ignores non-attached batteries" do
      battery_fixture(%{bldg_url: "g/home/detached", is_attached: false})
      assert Batteries.get_attached_battery_by_bldg_url("g/home/detached") == nil
    end

    test "create_battery/1 with valid data creates a battery" do
      assert {:ok, %Battery{} = battery} = Batteries.create_battery(@valid_attrs)
      assert battery.battery_type == "some battery_type"
      assert battery.battery_vendor == "some battery_vendor"
      assert battery.battery_version == "some battery_version"
      assert battery.bldg_url == "some bldg_url"
      assert battery.callback_url == "some callback_url"
      assert battery.direct_only == true
      assert battery.flr == "some flr"
      assert battery.is_attached == true
    end

    test "create_battery/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Batteries.create_battery(@invalid_attrs)
    end

    test "update_battery/2 with valid data updates the battery" do
      battery = battery_fixture()
      assert {:ok, %Battery{} = battery} = Batteries.update_battery(battery, @update_attrs)
      assert battery.battery_type == "some updated battery_type"
      assert battery.battery_vendor == "some updated battery_vendor"
      assert battery.battery_version == "some updated battery_version"
      assert battery.bldg_url == "some updated bldg_url"
      assert battery.callback_url == "some updated callback_url"
      assert battery.direct_only == false
      assert battery.flr == "some updated flr"
      assert battery.is_attached == false
    end

    test "update_battery/2 with invalid data returns error changeset" do
      battery = battery_fixture()
      assert {:error, %Ecto.Changeset{}} = Batteries.update_battery(battery, @invalid_attrs)
      assert battery == Batteries.get_battery!(battery.id)
    end

    test "delete_battery/1 deletes the battery" do
      battery = battery_fixture()
      assert {:ok, %Battery{}} = Batteries.delete_battery(battery)
      assert_raise Ecto.NoResultsError, fn -> Batteries.get_battery!(battery.id) end
    end

    test "change_battery/1 returns a battery changeset" do
      battery = battery_fixture()
      assert %Ecto.Changeset{} = Batteries.change_battery(battery)
    end
  end
end
