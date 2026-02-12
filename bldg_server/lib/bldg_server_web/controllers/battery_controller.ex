defmodule BldgServerWeb.BatteryController do
  use BldgServerWeb, :controller

  alias BldgServer.Batteries
  alias BldgServer.Batteries.Battery

  action_fallback(BldgServerWeb.FallbackController)

  def index(conn, _params) do
    batteries = Batteries.list_batteries()
    render(conn, "index.json", batteries: batteries)
  end

  def register(conn, %{"battery" => %{"battery_type" => battery_type, "callback_url" => callback_url}}) do
    # TODO must check authorization
    IO.puts("Registering battery type '#{battery_type}' with callback_url: #{callback_url}")

    case Batteries.register_battery(battery_type, callback_url) do
      {:ok, _count} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "registered", battery_type: battery_type, callback_url: callback_url})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to register battery", reason: inspect(reason)})
    end
  end

  def unregister(conn, %{"battery" => %{"battery_type" => battery_type, "callback_url" => callback_url}}) do
    # TODO must check authorization
    IO.puts("Unregistering battery type '#{battery_type}' callback_url: #{callback_url}")

    case Batteries.unregister_battery(battery_type, callback_url) do
      {:ok, _count} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "unregistered", battery_type: battery_type, callback_url: callback_url})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unregister battery", reason: inspect(reason)})
    end
  end

  def attach(conn, %{"battery" => battery_params}) do
    # add is_attached to the params
    IO.inspect(battery_params)
    battery_attrs = Map.merge(battery_params, %{"is_attached" => true})

    with {:ok, %Battery{} = battery} <- Batteries.create_battery(battery_attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.battery_path(conn, :show, battery))
      |> render("show.json", battery: battery)
    end
  end

  def detach(conn, %{"bldg_url" => bldg_url}) do
    IO.puts("Detaching battery from bldg #{bldg_url}")
    battery = Batteries.get_attached_battery_by_bldg_url!(bldg_url)

    with {:ok, %Battery{}} <- Batteries.delete_battery(battery) do
      send_resp(conn, :no_content, "")
    end
  end

  def create(conn, %{"battery" => battery_params}) do
    with {:ok, %Battery{} = battery} <- Batteries.create_battery(battery_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.battery_path(conn, :show, battery))
      |> render("show.json", battery: battery)
    end
  end

  def show(conn, %{"id" => id}) do
    battery = Batteries.get_battery!(id)
    render(conn, "show.json", battery: battery)
  end

  def update(conn, %{"id" => id, "battery" => battery_params}) do
    battery = Batteries.get_battery!(id)

    with {:ok, %Battery{} = battery} <- Batteries.update_battery(battery, battery_params) do
      render(conn, "show.json", battery: battery)
    end
  end

  def delete(conn, %{"id" => id}) do
    battery = Batteries.get_battery!(id)

    with {:ok, %Battery{}} <- Batteries.delete_battery(battery) do
      send_resp(conn, :no_content, "")
    end
  end
end
