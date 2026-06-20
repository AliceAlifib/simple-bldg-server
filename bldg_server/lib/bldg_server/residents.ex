defmodule BldgServer.Residents do
  @moduledoc """
  The Residents context.
  """

  import Ecto.Query, warn: false
  alias BldgServer.Repo

  alias BldgServer.Residents.Resident
  alias BldgServer.ResidentsAuth
  alias BldgServer.Buildings

  require Logger

  # alias BldgServerWeb.Router.Helpers, as: Routes


  @doc """
  Returns the list of residents.

  ## Examples

      iex> list_residents()
      [%Resident{}, ...]

  """
  def list_residents do
    Repo.all(Resident)
  end

  @doc """
  Returns all residents inside a given flr.

  Returns empty list if no such resident exists.
  """
  def list_residents_in_flr(flr) do
    q = from r in Resident, where: r.flr == ^flr
    Repo.all(q)
  end

  @doc """
  Returns all residents (including nested) inside a given flr.

  Returns empty list if no such resident exists.
  """
  def list_all_residents_in_flr(flr) do
    # Delimiter-safe: exact floor or a strict sub-path, so ".../l1" doesn't also
    # match ".../l10". See Buildings.list_all_bldgs_in_flr/2.
    q = from r in Resident,
        where: r.flr == ^flr or like(r.flr, ^"#{flr}/%")
    Repo.all(q)
  end


  @doc """
  Gets a single resident.

  Raises `Ecto.NoResultsError` if the Resident does not exist.

  ## Examples

      iex> get_resident!(123)
      %Resident{}

      iex> get_resident!(456)
      ** (Ecto.NoResultsError)

  """
  def get_resident!(id), do: Repo.get!(Resident, id)

  @doc """
  Gets a single resident by email.

  Raises `Ecto.NoResultsError` if the Resident does not exist.

  ## Examples

      iex> get_resident_by_email!("joe@doe.com")
      %Resident{}

      iex> get_resident!("notjoe@doe.com")
      ** (Ecto.NoResultsError)

  """
  def get_resident_by_email!(email), do: Repo.get_by!(Resident, email: email)

  def get_resident_by_email_and_session_id!(email, session_id), do: Repo.get_by!(Resident, email: email, session_id: session_id)

  @doc """
  Creates a resident.

  ## Examples

      iex> create_resident(%{field: value})
      {:ok, %Resident{}}

      iex> create_resident(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_resident(attrs \\ %{}) do
    result =
      %Resident{}
      |> Resident.changeset(attrs)
      |> Repo.insert()

    broadcast_resident_change(result, "resident_created")
    result
  end

  @doc """
  Updates a resident.

  ## Examples

      iex> update_resident(resident, %{field: new_value})
      {:ok, %Resident{}}

      iex> update_resident(resident, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_resident(%Resident{} = resident, attrs) do
    result =
      resident
      |> Resident.changeset(attrs)
      |> Repo.update()

    broadcast_resident_change(result, "resident_updated")
    result
  end

  @doc """
  Deletes a resident.

  ## Examples

      iex> delete_resident(resident)
      {:ok, %Resident{}}

      iex> delete_resident(resident)
      {:error, %Ecto.Changeset{}}

  """
  def delete_resident(%Resident{} = resident) do
    flr = resident.flr
    resident_id = resident.id
    result = Repo.delete(resident)

    case result do
      {:ok, _} ->
        if flr do
          BldgServer.Buildings.broadcast_to_floor_and_ancestors(flr, "resident_deleted", %{id: resident_id})
        end
      _ ->
        :ok
    end

    result
  end

  def start_email_verification(%Resident{} = resident, ip_addr) do
    {_, session} = ResidentsAuth.create_session(%{"session_id" => UUID.uuid4(), "resident_id" => resident.id, "email" => resident.email, "status" => ResidentsAuth.pending_verification, "ip_address" => ip_addr, "last_activity_time" => DateTime.utc_now()})
    token = BldgServer.Token.generate_login_token(session.session_id)
    #verification_url = Routes.resident_url(conn, :verify_email, token: token)  # doesn't work well with reverse proxy
    host = Application.get_env(:bldg_server, :app_hostname)
    # TODO Add the port for local dev. On prod, even though a port is configured, it isn't used in the URL since we have reverse proxy
    # TODO Don't hardcode the schema
    verification_url = "https://#{host}/v1/residents/verify?token=#{token}"
    BldgServer.Notifications.send_login_verification_email(resident, verification_url)
    IO.puts("Login started for #{resident.email}")
    {:verification_started, session.session_id}
  end


  @doc """
  Logs in a resident, following authentication.
  - location would be the last known location or home bldg.
  - should generate a new session_id
  - update last_login_at & is_online

  ## Examples

      iex> login(resident)
      {:ok, %Resident{}}

  """
  def login(conn, %Resident{} = resident) do
    ip_addr = conn.remote_ip |> :inet_parse.ntoa |> to_string()
    # check whether the resident has a verified session, from the same ip address, in the last week
    recent_session = ResidentsAuth.get_most_recent_verified_session(resident.id, ip_addr)
    if recent_session == [] do
      start_email_verification(resident, ip_addr)
    else
      [{session_id, updated_at}] = recent_session
      if Utils.is_newer_than_x_minutes_ago(updated_at, 60*24*7) do
        IO.puts("Login done for #{resident.email} - already has valid session")
        {:has_valid_session, session_id}
      else
        start_email_verification(resident, ip_addr)
      end
    end
  end

  def update_session_id(%Resident{} = resident, session_id) do
    changes = %{session_id: session_id, is_online: true, last_login_at: DateTime.utc_now()}
    update_resident(resident, changes)
  end

  @doc """
  Performs a move action for a resident, following validation of the action.
  Updates the location, x & y attributes.

  ## Examples

      iex> move(resident, "g/b(14, 25)", 14, 25)
      {:ok, %Resident{}}

  """
  def move(%Resident{} = resident, location, x, y) do
    changes = %{location: location, x: x, y: y}
    update_resident(resident, changes)
  end

  def calculate_nesting_depth_from_address(address) do
    num_slashes = address
    |> String.split(Buildings.address_delimiter)
    |> Enum.drop(1) |> length()
    case num_slashes do
      0 -> 0
      _ -> trunc((num_slashes + 1) / 2)
    end
  end

  def enter_bldg_flr(%Resident{} = resident, address, bldg_url, flr_level, post_enter_x, post_enter_y) do
    {initial_x, initial_y} = {post_enter_x, post_enter_y}
    nesting_depth = calculate_nesting_depth_from_address(address)
    case address do
      "g" ->
        changes = %{flr: "#{address}", flr_url: "#{bldg_url}", location: "#{address}/b(#{initial_x},#{initial_y})", x: initial_x, y: initial_y, nesting_depth: 0}
        update_resident(resident, changes)
      _ ->
        changes = %{flr: "#{address}/l#{flr_level}", flr_url: "#{bldg_url}/l#{flr_level}", location: "#{address}/l#{flr_level}/b(#{initial_x},#{initial_y})", x: initial_x, y: initial_y, nesting_depth: nesting_depth}
        update_resident(resident, changes)
    end
  end


  def enter_bldg(%Resident{} = resident, address, bldg_url, post_enter_x, post_enter_y) do
    enter_bldg_flr(resident, address, bldg_url, 0, post_enter_x, post_enter_y)
  end

  def enter_bldg(%Resident{} = resident, address, bldg_url) do
    enter_bldg_flr(resident, address, bldg_url, 0, 0, 0)
  end

  def exit_bldg(%Resident{} = resident, address, bldg_url, post_exit_x, post_exit_y) do
    # get the container flr
    container_flr = Buildings.get_container_flr(address)
    container_flr_url = Buildings.get_container_flr_url(bldg_url)

    # When the client doesn't supply a meaningful post-exit position (0/nil),
    # derive the landing spot from the exited bldg's own coords so the player
    # lands next to the bldg instead of at the floor origin. Honor explicit
    # non-zero coords as-is.
    {new_x, new_y} =
      case {post_exit_x, post_exit_y} do
        {x, y} when x in [0, nil] and y in [0, nil] ->
          {bx, by} = Buildings.extract_coords(address)
          {bx, by + 2}

        {x, y} ->
          {x, y}
      end

    nesting_depth = calculate_nesting_depth_from_address(container_flr)

    changes = %{flr: container_flr, flr_url: container_flr_url, location: "#{container_flr}/b(#{new_x},#{new_y})", x: new_x, y: new_y, nesting_depth: nesting_depth}
    update_resident(resident, changes)
  end

  def change_dir(%Resident{} = resident, direction) do
    changes = %{direction: direction}
    update_resident(resident, changes)
  end

  @doc """
  Updates the resident's view mode preference. Same broadcast path as the
  other update actions — the floor topic gets `resident_updated` so other
  clients of the same user can mirror the new mode in-place.
  """
  def change_view_mode(%Resident{} = resident, view_mode) do
    # Enforce the bird-eye invariant at runtime (it was previously only set by a
    # one-time migration): bird-eye residents always face 180. Other modes leave
    # the direction untouched.
    changes =
      case view_mode do
        "bird_eye" -> %{view_mode: view_mode, direction: 180}
        _ -> %{view_mode: view_mode}
      end

    update_resident(resident, changes)
  end

  def append_message_to_list(msg_list, msg) do
    case msg_list do
      nil -> [msg]
      _ -> [msg | msg_list]
    end
  end


  def is_command(msg_text), do: String.at(msg_text, 0) == "/"

  def say(%Resident{} = resident, msg) do
    {_, text} = msg
    |> Map.merge(%{"say_time" => System.system_time(:millisecond)})
    |> JSON.encode()

    prev_messages = Utils.limit_list_to(resident.previous_messages, 10)
    IO.puts("~~~~~ reduced list size to: #{Enum.count(prev_messages)}")

    new_prev_messages = append_message_to_list(prev_messages, text)
    changes = %{previous_messages: new_prev_messages}
    result = update_resident(resident, changes)

    # the message may be a command for bldg manipulation, so
    # broadcast an event for it, so that the command executor can process it
    if is_command(msg["say_text"]) do
      BldgServerWeb.Endpoint.broadcast!(
        "chat",
        "new_message",
        msg
      )
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking resident changes.

  ## Examples

      iex> change_resident(resident)
      %Ecto.Changeset{source: %Resident{}}

  """
  def change_resident(%Resident{} = resident) do
    Resident.changeset(resident, %{})
  end

  defp broadcast_resident_change({:ok, %Resident{} = resident}, event) do
    if resident.flr do
      payload = BldgServerWeb.FloorChannel.serialize_resident(resident)
      BldgServer.Buildings.broadcast_to_floor_and_ancestors(resident.flr, event, payload)
    end
  end

  defp broadcast_resident_change(_, _), do: :ok
end
