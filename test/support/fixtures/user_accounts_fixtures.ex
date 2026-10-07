defmodule LeastCostFeed.UserAccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `LeastCostFeed.UserAccounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> LeastCostFeed.UserAccounts.register_user()

    user
  end

  @doc """
  A user who can log in with email and password (login requires `confirmed_at`).

  Sets `confirmed_at` directly instead of going through `UserAccounts.confirm_user/1`,
  which also seeds the user's sample nutrients and ingredients.
  """
  def confirmed_user_fixture(attrs \\ %{}) do
    attrs
    |> user_fixture()
    |> LeastCostFeed.UserAccounts.User.confirm_changeset()
    |> LeastCostFeed.Repo.update!()
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
