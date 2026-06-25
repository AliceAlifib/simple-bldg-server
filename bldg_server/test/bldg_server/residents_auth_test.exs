defmodule BldgServer.ResidentsAuthTest do
  use BldgServer.DataCase

  alias BldgServer.ResidentsAuth

  describe "sessions" do
    alias BldgServer.ResidentsAuth.Session

    @valid_attrs %{email: "some email", ip_address: "some ip_address", last_activity_time: ~N[2010-04-17 14:00:00], resident_id: 42, session_id: "7488a646-e31f-11e4-aace-600308960662", status: "some status"}
    @update_attrs %{email: "some updated email", ip_address: "some updated ip_address", last_activity_time: ~N[2011-05-18 15:01:01], resident_id: 43, session_id: "7488a646-e31f-11e4-aace-600308960668", status: "some updated status"}
    @invalid_attrs %{email: nil, ip_address: nil, last_activity_time: nil, resident_id: nil, session_id: nil, status: nil}

    def session_fixture(attrs \\ %{}) do
      {:ok, session} =
        attrs
        |> Enum.into(@valid_attrs)
        |> ResidentsAuth.create_session()

      session
    end

    test "list_sessions/0 returns all sessions" do
      session = session_fixture()
      assert ResidentsAuth.list_sessions() == [session]
    end

    test "get_session!/1 returns the session with given id" do
      session = session_fixture()
      assert ResidentsAuth.get_session!(session.session_id) == session
    end

    test "create_session/1 with valid data creates a session" do
      assert {:ok, %Session{} = session} = ResidentsAuth.create_session(@valid_attrs)
      assert session.email == "some email"
      assert session.ip_address == "some ip_address"
      assert session.last_activity_time == ~N[2010-04-17 14:00:00]
      assert session.resident_id == 42
      assert session.session_id == "7488a646-e31f-11e4-aace-600308960662"
      assert session.status == "some status"
    end

    test "create_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = ResidentsAuth.create_session(@invalid_attrs)
    end

    test "update_session/2 with valid data updates the session" do
      session = session_fixture()
      assert {:ok, %Session{} = session} = ResidentsAuth.update_session(session, @update_attrs)
      assert session.email == "some updated email"
      assert session.ip_address == "some updated ip_address"
      assert session.last_activity_time == ~N[2011-05-18 15:01:01]
      assert session.resident_id == 43
      assert session.session_id == "7488a646-e31f-11e4-aace-600308960668"
      assert session.status == "some updated status"
    end

    test "update_session/2 with invalid data returns error changeset" do
      session = session_fixture()
      assert {:error, %Ecto.Changeset{}} = ResidentsAuth.update_session(session, @invalid_attrs)
      assert session == ResidentsAuth.get_session!(session.session_id)
    end

    test "delete_session/1 deletes the session" do
      session = session_fixture()
      assert {:ok, %Session{}} = ResidentsAuth.delete_session(session)
      assert_raise Ecto.NoResultsError, fn -> ResidentsAuth.get_session!(session.session_id) end
    end

    test "change_session/1 returns a session changeset" do
      session = session_fixture()
      assert %Ecto.Changeset{} = ResidentsAuth.change_session(session)
    end
  end
end
