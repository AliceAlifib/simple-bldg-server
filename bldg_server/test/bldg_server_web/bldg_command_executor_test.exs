defmodule BldgServerWeb.BldgCommandExecutorTest do
  use BldgServer.DataCase

  alias BldgServer.Buildings
  alias BldgServerWeb.BldgCommandExecutor

  @owner_email "owner@test.com"
  @other_email "stranger@test.com"
  @flr_url "g"
  @bldg_name "task_one"
  @bldg_url "g/task_one"

  @create_attrs %{
    "address" => "g/b(1,2)",
    "bldg_url" => @bldg_url,
    "flr" => @flr_url,
    "flr_url" => @flr_url,
    "flr_level" => 0,
    "nesting_depth" => 1,
    "is_composite" => false,
    "name" => @bldg_name,
    "entity_type" => "task",
    "state" => "Todo",
    "summary" => "",
    "category" => "",
    "picture_url" => "",
    "web_url" => "",
    "tags" => [],
    "x" => 1,
    "y" => 2,
    "owners" => [@owner_email]
  }

  # Insert the bldg directly (factory) rather than via Buildings.create_bldg/1,
  # whose notify cascade broadcasts chat commands handled asynchronously by the
  # BldgCommandExecutor GenServer (no sandbox access). The /edit tests only need
  # a bldg to exist; they don't exercise the create path.
  defp create_bldg(attrs \\ %{}) do
    bldg(Map.merge(@create_attrs, attrs))
  end

  defp msg(overrides \\ %{}) do
    Map.merge(
      %{
        "say_flr_url" => @flr_url,
        "resident_email" => @owner_email
      },
      overrides
    )
  end

  # Editing a bldg on "g" notifies up to the container floor, which looks up the
  # ground bldg — seed it so that lookup succeeds.
  setup do
    seed_ground_floor()
    :ok
  end

  describe "/edit command" do
    test "edits a single-word scalar field" do
      create_bldg()

      BldgCommandExecutor.execute_command(["/edit", @bldg_name, "state", "Done"], msg())

      assert Buildings.get_by_bldg_url(@bldg_url).state == "Done"
    end

    test "data edit preserves server-injected geometry keys" do
      create_bldg()
      bldg = Buildings.get_by_bldg_url(@bldg_url)
      # simulate add_composite_bldg_metadata's create-time injection
      {:ok, _} =
        Buildings.update_bldg(bldg, %{
          "data" => ~s({"flr0_height":"0.022","flr_height":"0.9"})
        })

      BldgCommandExecutor.execute_command(
        ["/edit", @bldg_name, "data", ~s({"id":47,"kind":"Ideas"})],
        msg()
      )

      data = JSON.decode!(Buildings.get_by_bldg_url(@bldg_url).data)
      assert data["id"] == 47 and data["kind"] == "Ideas"
      # geometry keys survive the payload that didn't mention them...
      assert data["flr0_height"] == "0.022" and data["flr_height"] == "0.9"

      # ...but an explicit value in the new payload wins
      BldgCommandExecutor.execute_command(
        ["/edit", @bldg_name, "data", ~s({"id":48,"flr0_height":"0.5"})],
        msg()
      )

      data = JSON.decode!(Buildings.get_by_bldg_url(@bldg_url).data)
      assert data["flr0_height"] == "0.5"
      assert data["flr_height"] == "0.9"
      refute Map.has_key?(data, "kind")
    end

    test "joins multi-word values with spaces" do
      create_bldg()

      BldgCommandExecutor.execute_command(
        ["/edit", @bldg_name, "summary", "a", "long", "description"],
        msg()
      )

      assert Buildings.get_by_bldg_url(@bldg_url).summary == "a long description"
    end

    test "splits tags value on commas into a list" do
      create_bldg()

      BldgCommandExecutor.execute_command(
        ["/edit", @bldg_name, "tags", "urgent,backend,q2"],
        msg()
      )

      assert Buildings.get_by_bldg_url(@bldg_url).tags == ["urgent", "backend", "q2"]
    end

    test "raises Unauthorized when speaker is not an owner" do
      create_bldg()

      assert_raise RuntimeError, ~r/Unauthorized/, fn ->
        BldgCommandExecutor.execute_command(
          ["/edit", @bldg_name, "state", "Done"],
          msg(%{"resident_email" => @other_email})
        )
      end

      assert Buildings.get_by_bldg_url(@bldg_url).state == "Todo"
    end

    test "raises when the bldg does not exist" do
      assert_raise RuntimeError, ~r/Bldg not found/, fn ->
        BldgCommandExecutor.execute_command(
          ["/edit", "missing_bldg", "state", "Done"],
          msg()
        )
      end
    end

    test "raises when the field is not in the editable whitelist" do
      create_bldg()

      assert_raise RuntimeError, ~r/not editable via chat/, fn ->
        BldgCommandExecutor.execute_command(
          ["/edit", @bldg_name, "address", "g/b(99,99)"],
          msg()
        )
      end

      assert_raise RuntimeError, ~r/not editable via chat/, fn ->
        BldgCommandExecutor.execute_command(
          ["/edit", @bldg_name, "owners", "someone@else.com"],
          msg()
        )
      end
    end

    test "raises when no value is provided" do
      create_bldg()

      assert_raise RuntimeError, ~r/Missing value/, fn ->
        BldgCommandExecutor.execute_command(["/edit", @bldg_name, "state"], msg())
      end
    end
  end
end
