use Mix.Config

# Configure your database
config :bldg_server, BldgServer.Repo,
  username: "postgres",
  password: System.get_env("DB_PASSWORD", "postgres"),
  database: "bldg_server_test",
  hostname: System.get_env("DB_HOST", "localhost"),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bldg_server, BldgServerWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn
