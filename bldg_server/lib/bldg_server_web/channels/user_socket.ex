defmodule BldgServerWeb.UserSocket do
  use Phoenix.Socket

  require Logger
  alias BldgServerWeb.{ResidentAuth, BatteryAuth}

  ## Channels
  channel "floor:*", BldgServerWeb.FloorChannel

  # Authenticate the socket from a `token` connect param (same bearer token as
  # the REST API). The resident is assigned for channel authorization. Dual-run:
  # when :enforce_auth is off, an anonymous socket is still accepted (logged);
  # once enforced, a missing/invalid token denies the connection.
  def connect(params, socket, _connect_info) do
    token = Map.get(params, "token")
    resident = ResidentAuth.resident_from_token(token)

    cond do
      resident ->
        {:ok, socket |> assign(:current_resident, resident) |> assign(:machine_authed, false)}

      # Machine principals (a battery — e.g. file-system-battery's floor-channel
      # transport — or the trusted service) authenticate with their key as the
      # `token` param.
      ResidentAuth.service_token?(token) || BatteryAuth.battery_key?(token) ->
        {:ok, socket |> assign(:current_resident, nil) |> assign(:machine_authed, true)}

      ResidentAuth.enforce_auth?() ->
        :error

      true ->
        Logger.warning("[auth] anonymous socket connect (dual-run: allowed)")
        {:ok, socket |> assign(:current_resident, nil) |> assign(:machine_authed, false)}
    end
  end

  # Identify sockets by resident so a revoked session can be force-disconnected:
  #     BldgServerWeb.Endpoint.broadcast("resident_socket:#{id}", "disconnect", %{})
  # Anonymous (dual-run) sockets return nil.
  def id(%{assigns: %{current_resident: %{id: rid}}}), do: "resident_socket:#{rid}"
  def id(_socket), do: nil
end
