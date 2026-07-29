defmodule BldgServerWeb.BatteryAuth do
  @moduledoc """
  Authentication for battery (machine) callers. A battery presents its service
  API key in `Authorization: Bearer <key>`; `fetch_current_battery/2` looks up
  the matching `battery_credentials` row and assigns `:current_battery`.

  Provisioning a key (via `POST /v1/batteries/register`) is gated by the
  out-of-band `BATTERY_PROVISION_TOKEN` (`require_battery_provisioning/2`).

  Like `ResidentAuth`, all rejection is gated by the `:enforce_auth` flag: in
  dual-run these plugs assign/pass and only log, so existing batteries keep
  working until they are updated to send keys.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  require Logger

  alias BldgServer.Batteries
  alias BldgServerWeb.ResidentAuth

  @doc "Plug: assign `:current_battery` from the Authorization bearer service key (nil if absent/invalid)."
  def fetch_current_battery(conn, _opts) do
    battery =
      case bearer_token(conn) do
        {:ok, key} -> Batteries.authenticate_battery_key(key)
        :error -> nil
      end

    assign(conn, :current_battery, battery)
  end

  @doc "Plug: require an authenticated battery. Halts 401 only when enforcing."
  def require_authenticated_battery(conn, _opts) do
    cond do
      conn.assigns[:current_battery] ->
        conn

      ResidentAuth.enforce_auth?() ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "battery authentication required"})
        |> halt()

      true ->
        Logger.warning(
          "[auth] unauthenticated battery #{conn.method} #{conn.request_path} (dual-run: allowed)"
        )

        conn
    end
  end

  @doc """
  Plug: require the out-of-band provisioning token for `register`. Accepted in
  the `X-Provision-Token` header or an `Authorization: Bearer` header. Halts 401
  only when enforcing; in dual-run it logs and passes.
  """
  def require_battery_provisioning(conn, _opts) do
    expected = Application.get_env(:bldg_server, :battery_provision_token)
    provided = provision_token(conn)

    cond do
      is_binary(expected) and expected != "" and secure_equal?(provided, expected) ->
        conn

      ResidentAuth.enforce_auth?() ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "battery provisioning token required"})
        |> halt()

      true ->
        Logger.warning("[auth] battery provisioning without valid token (dual-run: allowed)")
        conn
    end
  end

  defp provision_token(conn) do
    case get_req_header(conn, "x-provision-token") do
      [token | _] -> String.trim(token)
      _ ->
        case bearer_token(conn) do
          {:ok, token} -> token
          :error -> nil
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end

  defp secure_equal?(nil, _), do: false
  defp secure_equal?(a, b) when is_binary(a) and is_binary(b), do: Plug.Crypto.secure_compare(a, b)
  defp secure_equal?(_, _), do: false
end
