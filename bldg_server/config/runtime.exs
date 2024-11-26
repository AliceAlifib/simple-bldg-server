# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
import Config

if config_env() == :prod do

  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  app_port = System.fetch_env!("APP_PORT")
  app_hostname = System.fetch_env!("APP_HOSTNAME")
  db_user = System.fetch_env!("DB_USER")
  db_password = System.fetch_env!("DB_PASSWORD")
  db_host = System.fetch_env!("DB_HOST")
  {db_port, _} = Integer.parse(System.fetch_env!("DB_PORT")) # TODO add default value
  db_name = System.fetch_env!("DB_NAME")
  db_ssl = System.fetch_env!("DB_SSL") == "true"   # TODO add default value

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
    pool_size: 10#,
    #socket_options: [:inet6]

end

config :bldg_server, BldgServer.Mailer,
  adapter: Bamboo.SendGridAdapter,
  api_key: System.get_env("SENDGRID_API_KEY"),
  hackney_opts: [
    recv_timeout: :timer.minutes(1)
  ]


# ## Using releases (Elixir v1.9+)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint:
#
config :bldg_server, BldgServerWeb.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.
