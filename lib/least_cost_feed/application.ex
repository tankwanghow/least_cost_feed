defmodule LeastCostFeed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LeastCostFeedWeb.Telemetry,
      LeastCostFeed.Repo,
      {DNSCluster, query: Application.get_env(:least_cost_feed, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LeastCostFeed.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: LeastCostFeed.Finch},
      # Start a worker by calling: LeastCostFeed.Worker.start_link(arg)
      # {LeastCostFeed.Worker, arg},
      # Start to serve requests, typically the last entry
      LeastCostFeedWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LeastCostFeed.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LeastCostFeedWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
