defmodule LeastCostFeed.Repo do
  use Ecto.Repo,
    otp_app: :least_cost_feed,
    adapter: Ecto.Adapters.Postgres
end
