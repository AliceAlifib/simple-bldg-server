defmodule BldgServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  def start(_type, _args) do
    # Route :logger error/crash events into Sentry. Only attaches when a DSN
    # is configured — local dev without SENTRY_DSN is a no-op.
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    redis_host = System.fetch_env!("REDIS_HOST")
    redis_password = System.fetch_env!("REDIS_PWD")
    redis_port = System.fetch_env!("REDIS_PORT") || "6379"

    # Never log the Redis password. Log only non-secret connection facts.
    Logger.info(
      "Redis configuration - Host: #{redis_host}, Port: #{redis_port}, Auth: #{redis_password not in [nil, ""]}"
    )

    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      BldgServer.Repo,
      # Start the endpoint when the application starts
      BldgServerWeb.Endpoint,
      # Starts a worker by calling: BldgServer.Worker.start_link(arg)
      # {BldgServer.Worker, arg},
      BldgServerWeb.BldgCommandExecutor,
      BldgServerWeb.BatteryChatDispatcher,
      # Start the http client
      {Finch, name: FinchClient},
      # Start the redis connection
      {Redix,
       [
         host: redis_host,
         # Treat a blank REDIS_PWD as "no auth" so the client doesn't send
         # `AUTH ""` (which a password-less Redis rejects). Prod sets a real
         # password, so its behavior is unchanged; this only helps the common
         # password-less local/CI Redis used by the test suite.
         password: if(redis_password in [nil, ""], do: nil, else: redis_password),
         port: String.to_integer(redis_port),
         socket_opts: [:inet6],
         name: :redix
       ]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BldgServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    BldgServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
