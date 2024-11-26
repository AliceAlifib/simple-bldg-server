defmodule BldgServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
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
      {Redix, [
        host: System.get_env("REDIS_HOST"),
        #password: System.get_env("REDIS_PASSWORD"),
        port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
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
