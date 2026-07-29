defmodule BldgServerWeb.ResidentAuth do
  @moduledoc """
  Authentication/authorization for resident-facing API and WebSocket requests
  (phx.gen.auth `UserAuth` pattern).

  The credential is a `BldgServer.Token` bearer token in `Authorization: Bearer
  <token>`, issued on magic-link verification. `fetch_current_resident/2`
  verifies it, loads the backing `sessions` row, requires it be `VERIFIED`
  (the sessions table is the revocation list), and assigns
  `conn.assigns.current_resident`.

  ## Dual-run

  Everything here is gated by the `:enforce_auth` app flag. When it is `false`
  (the rollout default) `require_authenticated_resident/2` and the `authorize_*`
  helpers never reject — they only log what they *would* have blocked — so
  existing unauthenticated clients keep working. Flip the flag to `true` once
  clients send tokens.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  require Logger

  alias BldgServer.{Buildings, Residents, ResidentsAuth}
  alias BldgServer.ResidentsAuth.Session

  def enforce_auth?, do: Application.get_env(:bldg_server, :enforce_auth, false)

  # --- Trusted service (alice-in-goals provisioner) -------------------------
  # A first-party backend that presents the shared BLDG_SERVER_API_KEY as a
  # bearer token. It provisions residents/bldgs and mints resident tokens, so it
  # is treated as a privileged caller that bypasses per-resident ownership.

  def service_api_key, do: Application.get_env(:bldg_server, :service_api_key)

  @doc "True when the request carries the configured service API key."
  def service?(conn), do: conn.assigns[:current_service] == true

  @doc "Plug: assign `:current_service` when the bearer token equals the service API key."
  def fetch_current_service(conn, _opts) do
    key = service_api_key()

    is_service =
      is_binary(key) and key != "" and
        case bearer_token(conn) do
          {:ok, token} -> Plug.Crypto.secure_compare(token, key)
          :error -> false
        end

    assign(conn, :current_service, is_service)
  end

  @doc """
  Plug: require the trusted service API key. Unlike the resident/battery plugs
  this is ALWAYS enforced (never relaxed in dual-run) — it guards privileged
  operations like minting resident tokens, which must never be open.
  """
  def require_authenticated_service(conn, _opts) do
    if service?(conn) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "service authentication required"})
      |> halt()
    end
  end

  @doc """
  Resolves a resident from a bearer token (or nil). Shared by the plug and the
  WebSocket `connect/3`.
  """
  def resident_from_token(token) when is_binary(token) do
    with {:ok, %{resident_id: rid, session_id: sid}} <- BldgServer.Token.verify_auth_token(token),
         %Session{} = session <- ResidentsAuth.get_session_by_session_id(sid),
         ^rid <- session.resident_id,
         verified when verified == session.status <- ResidentsAuth.verified() do
      safe_get_resident(rid)
    else
      _ -> nil
    end
  end

  def resident_from_token(_), do: nil

  @doc "Plug: assign `:current_resident` from the Authorization bearer token (nil if absent/invalid)."
  def fetch_current_resident(conn, _opts) do
    resident =
      case bearer_token(conn) do
        {:ok, token} -> resident_from_token(token)
        :error -> nil
      end

    assign(conn, :current_resident, resident)
  end

  @doc "Plug: require an authenticated resident. Halts 401 only when enforcing."
  def require_authenticated_resident(conn, _opts) do
    cond do
      conn.assigns[:current_resident] || service?(conn) ->
        conn

      enforce_auth?() ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "authentication required"})
        |> halt()

      true ->
        Logger.warning(
          "[auth] unauthenticated #{conn.method} #{conn.request_path} (dual-run: allowed)"
        )

        conn
    end
  end

  @doc """
  The email to attribute an action to: the authenticated resident's when
  present, otherwise the caller-supplied fallback (dual-run). Once enforcement is
  on, `require_authenticated_resident` guarantees `current_resident` is set, so
  the fallback is never reached on a protected route.
  """
  def acting_email(conn, fallback) do
    case conn.assigns[:current_resident] do
      %{email: email} -> email
      _ -> fallback
    end
  end

  @doc """
  Authorizes the current resident to mutate `bldg` (direct owner or via an
  ancestor container). Returns `:ok` or `{:error, :forbidden}`. In dual-run it
  logs a would-be denial and returns `:ok`.
  """
  def authorize_bldg(conn, %Buildings.Bldg{} = bldg) do
    authorize(conn, fn email -> Buildings.is_authorized_owner?(email, bldg) end, bldg.bldg_url)
  end

  def authorize_bldg(conn, nil), do: authorize(conn, fn _ -> false end, "nil-bldg")

  @doc "Authorizes the current resident against a bldg resolved from a floor (its container)."
  def authorize_container(conn, flr) do
    container =
      case Buildings.get_flr_bldg(flr) do
        nil -> nil
        addr -> safe_get_bldg(addr)
      end

    authorize(conn, fn email -> Buildings.is_authorized_owner?(email, container) end, "flr:#{flr}")
  end

  @doc "Authorizes that the current resident is `resident_id` themselves (self-only actions)."
  def authorize_self(conn, resident_id) do
    current = conn.assigns[:current_resident]

    cond do
      service?(conn) ->
        :ok

      current && to_string(current.id) == to_string(resident_id) ->
        :ok

      enforce_auth?() ->
        {:error, :forbidden}

      true ->
        Logger.warning("[auth] self-check bypassed in dual-run for resident ##{resident_id}")
        :ok
    end
  end

  defp authorize(conn, ownership_fun, label) do
    email = case conn.assigns[:current_resident] do
      %{email: email} -> email
      _ -> nil
    end

    cond do
      service?(conn) ->
        :ok

      email && ownership_fun.(email) ->
        :ok

      enforce_auth?() ->
        {:error, :forbidden}

      true ->
        Logger.warning("[auth] ownership check bypassed in dual-run for #{label}")
        :ok
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end

  defp safe_get_resident(rid) do
    Residents.get_resident!(rid)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp safe_get_bldg(address) do
    Buildings.get_bldg!(address)
  rescue
    Ecto.NoResultsError -> nil
  end
end
