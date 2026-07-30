defmodule LeastCostFeed.UserAccounts.UserNotifierTest do
  # async: false — these tests mutate application env, which is global state.
  use ExUnit.Case, async: false

  alias LeastCostFeed.UserAccounts.UserNotifier

  setup do
    original = Application.fetch_env(:least_cost_feed, :mail_from)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:least_cost_feed, :mail_from, value)
        :error -> Application.delete_env(:least_cost_feed, :mail_from)
      end
    end)

    :ok
  end

  test "uses the configured :mail_from address" do
    Application.put_env(:least_cost_feed, :mail_from, {"LeastCostFeed", "noreply@example.com"})

    {:ok, email} =
      UserNotifier.deliver_confirmation_instructions(
        %{email: "user@example.com"},
        "http://localhost/confirm/abc"
      )

    assert email.from == {"LeastCostFeed", "noreply@example.com"}
  end

  test "falls back to the default address when :mail_from is unset" do
    Application.delete_env(:least_cost_feed, :mail_from)

    {:ok, email} =
      UserNotifier.deliver_confirmation_instructions(
        %{email: "user@example.com"},
        "http://localhost/confirm/abc"
      )

    assert email.from == {"LeastCostFeed", "tankwanghow@gmail.com"}
  end
end
