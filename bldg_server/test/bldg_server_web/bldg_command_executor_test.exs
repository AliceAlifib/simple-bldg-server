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

  defp create_bldg(attrs \\ %{}) do
    {:ok, bldg} = Buildings.create_bldg(Map.merge(@create_attrs, attrs))
    bldg
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

  describe "/edit command" do
    test "edits a single-word scalar field" do
      create_bldg()

      BldgCommandExecutor.execute_command(["/edit", @bldg_name, "state", "Done"], msg())

      assert Buildings.get_by_bldg_url(@bldg_url).state == "Done"
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
