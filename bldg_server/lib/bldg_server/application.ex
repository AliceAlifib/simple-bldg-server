defmodule BldgServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  def start(_type, _args) do
    # Log Redis configuration for debugging
    redis_host = System.fetch_env!("REDIS_HOST")
    redis_password = System.fetch_env!("REDIS_PWD")
    redis_port = System.fetch_env!("REDIS_PORT") || "6379"

    Logger.info(
      "Redis configuration - Host: #{redis_host}, Port: #{redis_port}, Pwd: #{redis_password}"
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
         password: redis_password,
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
