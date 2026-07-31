# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :bldg_server,
  ecto_repos: [BldgServer.Repo]

# SSRF guard (BldgServer.SafeUrl): block battery callback_urls that resolve to
# private/loopback/link-local addresses. Strict by default (prod); dev/test
# relax it to allow loopback for Bypass mock servers and local batteries.
config :bldg_server, :block_private_callback_urls, true

# Auth enforcement (dual-run rollout). false = authn plugs assign identity and
# log unauthenticated calls but never reject (existing clients keep working);
# true = the API/WS require a valid bearer/service token. Overridable at runtime
# via ENFORCE_AUTH (see config/runtime.exs). Keep false until the Unity client
# and batteries send tokens, then flip.
config :bldg_server, :enforce_auth, false

# Configures the endpoint.
# secret_key_base is sourced from the environment in config/runtime.exs (all
# environments) so no secret material lives in source. There is no cookie
# session or LiveView in this JSON API — "sessions" are DB rows in the
# `sessions` table — so no session/live_view signing salt is configured.
config :bldg_server, BldgServerWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: BldgServerWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: BldgServer.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Redact sensitive fields from Phoenix's request-parameter logging. Any param
# whose key contains one of these substrings is logged as "[FILTERED]".
config :phoenix, :filter_parameters,
  ["password", "token", "session_id", "callback_url", "secret", "authorization", "email"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
