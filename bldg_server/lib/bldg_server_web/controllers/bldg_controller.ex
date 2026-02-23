defmodule BldgServerWeb.BldgController do
  use BldgServerWeb, :controller

  alias BldgServer.Buildings
  alias BldgServer.Buildings.Bldg

  action_fallback(BldgServerWeb.FallbackController)

  def index(conn, _params) do
    bldgs = Buildings.list_bldgs()
    render(conn, "index.json", bldgs: bldgs)
  end

  def create(conn, %{"bldg" => bldg_params}) do
    IO.puts("~~~ create")
    IO.inspect(bldg_params)

    case Buildings.create_bldg(bldg_params) do
      {:ok, %Bldg{} = bldg} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", Routes.bldg_path(conn, :show, bldg))
        |> render("show.json", bldg: bldg)

      {:error, error_message} ->
        IO.puts(error_message)
    end
  end

  def show(conn, %{"address" => address}) do
    # unescape the address parameter
    decoded_address = URI.decode(address)
    bldg = Buildings.get_bldg!(decoded_address)
    render(conn, "show.json", bldg: bldg)
  end

  def update(conn, %{"address" => address, "bldg" => bldg_params}) do
    bldg = Buildings.get_bldg!(address)

    with {:ok, %Bldg{} = bldg} <- Buildings.update_bldg(bldg, bldg_params) do
      render(conn, "show.json", bldg: bldg)
    end
  end

  def delete(conn, %{"address" => address}) do
    bldg = Buildings.get_bldg!(address)

    with {:ok, %Bldg{}} <- Buildings.delete_bldg(bldg) do
      send_resp(conn, :no_content, "")
    end
  end

  def look(conn, %{"flr" => flr}) do
    # unescape the flr parameter
    decoded_flr = URI.decode(flr)
    container_bldg_addr = Buildings.get_flr_bldg(decoded_flr)
    container = Buildings.get_bldg!(container_bldg_addr)
    bldgs = Buildings.list_bldgs_in_flr(decoded_flr)
    render(conn, "look.json", bldgs: [container | bldgs])
  end

  def scan(conn, %{"flr" => flr}) do
    decoded_flr = URI.decode(flr)
    container_bldg_addr = Buildings.get_flr_bldg(decoded_flr)
    container = Buildings.get_bldg!(container_bldg_addr)
    bldgs = Buildings.list_all_bldgs_in_flr(decoded_flr)
    render(conn, "look.json", bldgs: [container | bldgs])
  end

  def build(conn, %{"entity" => entity}) do
    bldg = Buildings.build(entity)
    create(conn, %{"bldg" => bldg})
  end

  def relocate(conn, %{"address" => address, "new_address" => new_address}) do
    {new_x, new_y} = Buildings.extract_coords(new_address)
    bldg_params = %{"address" => new_address, "x" => new_x, "y" => new_y}
    update(conn, %{"address" => address, "bldg" => bldg_params})
  end

  @doc """
  Receives a web_url & returns the address of the bldg matching it.
  """
  def resolve_address(conn, %{"web_url" => escaped_web_url}) do
    web_url = URI.decode(escaped_web_url)

    case Buildings.get_by_web_url(web_url) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("Coudn't find a matching building")

      bldg ->
        text(conn, bldg.address)
    end
  end

  # SAY action
  def act(
        conn,
        %{
          "action_type" => "SAY",
          "resident_email" => email,
          "bldg_url" => bldg_url,
          "say_flr_url" => _flr_url,
          "say_speaker" => _speaker,
          "say_text" => _text
        } = msg
      ) do
    bldg = Buildings.get_by_bldg_url(bldg_url)
    # TODO verify that the battery has a valid session & access & chat permissions in this bldg

    # TODO - TECH DEBT!!! - temp code that needs to be cleaned
    # msg_with_say_flr =
    #   case Map.get(msg, "say_flr") do
    #     nil -> Map.put(msg, "say_flr", "#{bldg.address}/l0")
    #     _ -> msg
    #   end

    # msg_with_say_location =
    #   case Map.get(msg_with_say_flr, "say_location") do
    #     nil -> Map.put(msg_with_say_flr, "say_location", "#{bldg.address}/l0/b(0,0)")
    #     _ -> msg_with_say_flr
    #   end

    # This can stay
    msg_with_say_time =
      case Map.get(msg, "say_time") do
        nil -> Map.put(msg, "say_time", System.system_time(:millisecond))
        _ -> msg
      end

    case Buildings.say(bldg, msg_with_say_time) do
      {:ok, %Bldg{} = upd_bldg} ->
        conn
        |> put_status(:ok)
        |> put_resp_header("location", Routes.bldg_path(conn, :show, upd_bldg))
        |> render("show.json", bldg: upd_bldg)

      {:error, e} ->
        IO.inspect(e)
    end
  end
end
