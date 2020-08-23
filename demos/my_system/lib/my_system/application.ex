defmodule MySystem.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Boundary, top_level?: true, deps: [MySystem, MySystemWeb]
  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the endpoint when the application starts
      MySystemWeb.Endpoint
      # Starts a worker by calling: MySystem.Worker.start_link(arg)
      # {MySystem.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MySystem.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MySystemWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def foo(), do: :ok
end
