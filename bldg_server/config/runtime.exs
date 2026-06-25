# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
import Config

# Sentry error reporting — active in any env where SENTRY_DSN is set (prod).
# No-op when the env var is absent (dev/test), so local work is unaffected.
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: to_string(config_env()),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  tags: %{service: "bldg-server", fly_app: System.get_env("FLY_APP_NAME")}

if config_env() == :test do
  # application.ex reads these via System.fetch_env! at boot. Provide localhost
  # defaults so `mix test` works out of the box against a standard password-less
  # Redis; CI or a developer can override by exporting REDIS_* before the suite.
  System.put_env("REDIS_HOST", System.get_env("REDIS_HOST") || "localhost")
  System.put_env("REDIS_PORT", System.get_env("REDIS_PORT") || "6379")
  System.put_env("REDIS_PWD", System.get_env("REDIS_PWD") || "")
end

if config_env() == :prod do
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  app_port = System.fetch_env!("APP_PORT")
  app_hostname = System.fetch_env!("APP_HOSTNAME")
  db_user = System.fetch_env!("DB_USER")
  db_password = System.fetch_env!("DB_PASSWORD")
  db_host = System.fetch_env!("DB_HOST")
  # TODO add default value
  {db_port, _} = Integer.parse(System.fetch_env!("DB_PORT"))
  db_name = System.fetch_env!("DB_NAME")
  db_ssl = System.fetch_env!("DB_SSL") == "true"
  # TODO add default value
  dgraph_url = System.fetch_env!("DGRAPH_URL")

  config :bldg_server, :dgraph_url, dgraph_url

  config :bldg_server, BldgServerWeb.Endpoint,
    http: [:inet6, port: String.to_integer(app_port)],
    secret_key_base: secret_key_base

  config :bldg_server,
    app_port: app_port

  config :bldg_server,
    app_hostname: app_hostname

  # Configure your database
  config :bldg_server, BldgServer.Repo,
    username: db_user,
    password: db_password,
    database: db_name,
    hostname: db_host,
    port: db_port,
    ssl: db_ssl,
    pool_size: 20,
    queue_target: 5000,
    # ,
    queue_interval: 10000,
    socket_options: [:inet6]
end

# Test uses Bamboo.TestAdapter (set in config/test.exs); don't clobber it here.
# runtime.exs is evaluated after compile-time config, so this block would
# otherwise override the test adapter and make login tests hit SendGrid.
unless config_env() == :test do
  config :bldg_server, BldgServer.Mailer,
    adapter: Bamboo.SendGridAdapter,
    api_key: System.get_env("SENDGRID_API_KEY"),
    hackney_opts: [
      recv_timeout: :timer.minutes(1)
    ]
end

# ## Using releases (Elixir v1.9+)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint:
#
config :bldg_server, BldgServerWeb.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.
