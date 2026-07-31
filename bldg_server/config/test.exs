use Mix.Config

# Configure your database
config :bldg_server, BldgServer.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  database: "bldg_server_test",
  hostname: System.get_env("DB_HOST", "localhost"),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bldg_server, BldgServerWeb.Endpoint,
  http: [port: 4002],
  server: false

# Capture outbound mail in-memory instead of hitting SendGrid. Tests can then
# assert delivery with `Bamboo.Test`'s `assert_delivered_email/1`.
config :bldg_server, BldgServer.Mailer, adapter: Bamboo.TestAdapter

# Point the DGraph client at a local default; staging tests override this to a
# Bypass port via Application.put_env at runtime.
config :bldg_server, :dgraph_url, "http://localhost:8080"

# Bypass mock servers bind to loopback, so allow private callback_urls in tests.
config :bldg_server, :block_private_callback_urls, false

# Print only warnings and errors during test
config :logger, level: :warn
