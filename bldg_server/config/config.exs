# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :bldg_server,
  ecto_repos: [BldgServer.Repo]

# Configures the endpoint
config :bldg_server, BldgServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "t2WDNZ4f2koI3NJfZcKhdxZyRhHfbqLf+VBDhCYezzQHzw/tMA9jcXSBGtU5F20C",
  render_errors: [view: BldgServerWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: BldgServer.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [signing_salt: "37nH1WIX"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bldg_server, BldgServer.Mailer,
  adapter: Bamboo.SendGridAdapter,
  api_key: System.get_env("SENDGRID_API_KEY"),
  hackney_opts: [
    recv_timeout: :timer.minutes(1)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
