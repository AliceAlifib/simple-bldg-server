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
  # Redact credentials/PII from every event before it is sent (see scrubber).
  before_send: {BldgServer.SentryScrubber, :before_send},
  tags: %{service: "bldg-server", fly_app: System.get_env("FLY_APP_NAME")}

# --- Signing secrets (all environments) -------------------------------------
# The real secret is SECRET_KEY_BASE; Phoenix derives every per-purpose signing
# key from it plus a salt (so the token salts are namespaces, not secrets). In
# prod a missing/blank value fails loud; dev and test fall back to clearly
# non-secret local defaults so the app boots with zero configuration.
fetch_secret = fn var, dev_default ->
  case System.get_env(var) do
    value when value in [nil, ""] ->
      if config_env() == :prod,
        do: raise("environment variable #{var} is missing or empty"),
        else: dev_default

    value ->
      value
  end
end

config :bldg_server, BldgServerWeb.Endpoint,
  secret_key_base:
    fetch_secret.(
      "SECRET_KEY_BASE",
      "dev_only_insecure_secret_key_base_override_in_prod_padding_0123456789"
    )

# Phoenix.Token salts for the magic-link verification token and (Tranche 2) the
# resident bearer token. Distinct salts keep the two token classes unforgeable
# across purposes.
config :bldg_server,
  magic_link_salt: fetch_secret.("MAGIC_LINK_SALT", "dev_only_magic_link_salt"),
  auth_token_salt: fetch_secret.("AUTH_TOKEN_SALT", "dev_only_auth_token_salt")

# CORS allow-list (read by BldgServerWeb.Endpoint.cors_origins/0). CORS only
# constrains browsers; the Unity client and batteries send no Origin header and
# are unaffected. Prod defaults to deny-all so a web origin must be added
# explicitly via CORS_ORIGINS (comma-separated); dev reflects any origin.
cors_origins =
  case System.get_env("CORS_ORIGINS") do
    nil -> if config_env() == :prod, do: [], else: ["*"]
    "" -> []
    value -> value |> String.split(",") |> Enum.map(&String.trim/1)
  end

config :bldg_server, :cors_origins, cors_origins

# Auth enforcement toggle for the dual-run rollout. Read from ENFORCE_AUTH so it
# can be flipped in prod without a code deploy. Defaults to the compile-time
# value (false) when the var is unset.
if System.get_env("ENFORCE_AUTH") do
  config :bldg_server, :enforce_auth, System.get_env("ENFORCE_AUTH") == "true"
end

# Out-of-band secret that gates battery credential provisioning (the bootstrap
# for a machine caller that can't do the email magic-link). Optional in dev/test.
config :bldg_server,
  battery_provision_token: System.get_env("BATTERY_PROVISION_TOKEN")

if config_env() == :test do
  # application.ex reads these via System.fetch_env! at boot. Provide localhost
  # defaults so `mix test` works out of the box against a standard password-less
  # Redis; CI or a developer can override by exporting REDIS_* before the suite.
  System.put_env("REDIS_HOST", System.get_env("REDIS_HOST") || "localhost")
  System.put_env("REDIS_PORT", System.get_env("REDIS_PORT") || "6379")
  System.put_env("REDIS_PWD", System.get_env("REDIS_PWD") || "")
end

if config_env() == :prod do
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

  # TLS is terminated at the Fly edge (force_https in fly.*.toml); the app speaks
  # HTTP internally but receives the original scheme via x-forwarded-proto.
  # force_ssl redirects any plain-HTTP request and, with hsts: true, emits a
  # Strict-Transport-Security header so browsers refuse future HTTP.
  config :bldg_server, BldgServerWeb.Endpoint,
    http: [:inet6, port: String.to_integer(app_port)],
    force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]

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
