defmodule BldgServerWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :bldg_server

  # This is a JSON API with no cookie session and no LiveView: resident
  # "sessions" are rows in the `sessions` table and the API credential is a
  # bearer token (see BldgServer.Token). No Plug.Session is mounted, so there is
  # no signing salt to keep in source.

  # CORS allow-list. Sourced from the CORS_ORIGINS env var (comma-separated) via
  # config/runtime.exs; prod defaults to deny-all (empty list) so a browser
  # origin must be added explicitly, dev reflects any origin. Evaluated per
  # request so the runtime config is honored.
  def cors_origins, do: Application.get_env(:bldg_server, :cors_origins, [])

  socket "/socket", BldgServerWeb.UserSocket,
    websocket: true,
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :bldg_server,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug CORSPlug, origin: &BldgServerWeb.Endpoint.cors_origins/0
  plug BldgServerWeb.Router
end
