defmodule BldgServerWeb.BatteryController do
  use BldgServerWeb, :controller
  require Logger

  alias BldgServer.Batteries
  alias BldgServer.Batteries.Battery
  alias BldgServerWeb.ResidentAuth

  action_fallback(BldgServerWeb.FallbackController)

  def index(conn, _params) do
    batteries = Batteries.list_batteries()
    render(conn, "index.json", batteries: batteries)
  end

  # Provisioning is gated by the :battery_provisioning pipeline (out-of-band
  # token). When the body carries an `owner_email`, a service credential is
  # provisioned and its plaintext key returned once as `api_key`; existing
  # callers that omit it just register the callback (dual-run).
  def register(conn, %{"battery" => %{"battery_type" => battery_type, "callback_url" => callback_url} = params}) do
    Logger.info("Registering battery type '#{battery_type}'")

    case Batteries.register_battery(battery_type, callback_url) do
      {:ok, _count} ->
        resp =
          %{status: "registered", battery_type: battery_type, callback_url: callback_url}
          |> maybe_provision(battery_type, params)

        conn
        |> put_status(:ok)
        |> json(resp)

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to register battery", reason: inspect(reason)})
    end
  end

  @doc """
  Provisions a scoped battery API key (service-authenticated; see router). Used
  by the alice-in-goals provisioner to mint a per-sprite battery's credential and
  inject it into the sprite — so no shared master secret ever lands in a sprite.
  Returns the plaintext key once. Does NOT register a callback (the battery does
  that itself with its key).
  """
  def provision_credential(conn, %{"battery_type" => battery_type, "owner_email" => owner_email}) do
    case Batteries.provision_battery_credential(battery_type, owner_email) do
      {:ok, key, _cred} ->
        conn
        |> put_status(:created)
        |> json(%{api_key: key, battery_type: battery_type, owner_email: owner_email})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to provision credential", details: inspect(changeset.errors)})
    end
  end

  def unregister(conn, %{"battery" => %{"battery_type" => battery_type, "callback_url" => callback_url}}) do
    with :ok <- authorize_battery_type(conn, battery_type),
         {:ok, _count} <- Batteries.unregister_battery(battery_type, callback_url) do
      Logger.info("Unregistering battery type '#{battery_type}'")

      conn
      |> put_status(:ok)
      |> json(%{status: "unregistered", battery_type: battery_type, callback_url: callback_url})
    else
      {:error, :forbidden} = err ->
        err

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unregister battery", reason: inspect(reason)})
    end
  end

  # A battery may only unregister callbacks for its own battery_type. Gated by
  # enforce_auth: in dual-run it logs and allows.
  defp authorize_battery_type(conn, battery_type) do
    case conn.assigns[:current_battery] do
      %{battery_type: ^battery_type} ->
        :ok

      _ ->
        if ResidentAuth.enforce_auth?() do
          {:error, :forbidden}
        else
          :ok
        end
    end
  end

  defp maybe_provision(resp, battery_type, %{"owner_email" => owner_email})
       when is_binary(owner_email) and owner_email != "" do
    case Batteries.provision_battery_credential(battery_type, owner_email) do
      {:ok, key, _cred} -> Map.put(resp, :api_key, key)
      {:error, _} -> resp
    end
  end

  defp maybe_provision(resp, _battery_type, _params), do: resp

  def attach(conn, %{"battery" => battery_params}) do
    battery_attrs = Map.merge(battery_params, %{"is_attached" => true})

    with {:ok, %Battery{} = battery} <- Batteries.create_battery(battery_attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.battery_path(conn, :show, battery))
      |> render("show.json", battery: battery)
    end
  end

  def detach(conn, %{"bldg_url" => bldg_url}) do
    Logger.info("Detaching battery from bldg #{bldg_url}")
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
