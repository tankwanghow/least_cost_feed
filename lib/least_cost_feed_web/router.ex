defmodule LeastCostFeedWeb.Router do
  use LeastCostFeedWeb, :router

  import LeastCostFeedWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LeastCostFeedWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LeastCostFeedWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", LeastCostFeedWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:least_cost_feed, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LeastCostFeedWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LeastCostFeedWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{LeastCostFeedWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", LeastCostFeedWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{LeastCostFeedWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email

      live "/nutrients", NutrientLive.Index, :index
      live "/nutrients/new", NutrientLive.Form, :new
      live "/nutrients/:id/edit", NutrientLive.Form, :edit

      live "/ingredients", IngredientLive.Index, :index
      live "/ingredients/new", IngredientLive.Form, :new
      live "/ingredients/:id/edit", IngredientLive.Form, :edit
      live "/ingredient_usages", IngredientLive.Usage, :index

      live "/formulas", FormulaLive.Index, :index
      live "/formulas/new", FormulaLive.Form, :new
      live "/formulas/:id/edit", FormulaLive.Form, :edit
      live "/formulas/copy/:id", FormulaLive.Form, :copy

      live "/formula_premix/:id/edit", PremixLive.Form, :edit

      live "/transfer", TransferLive.Form
    end

    live_session :require_authenticated_user_print,
      on_mount: [{LeastCostFeedWeb.UserAuth, :ensure_authenticated}],
      root_layout: {LeastCostFeedWeb.Layouts, :print_root} do
      live "/formulas/print_multi", FormulaLive.FormulaPrint, :print
      live "/formulas_premix/print_multi", FormulaLive.PremixPrint, :print
    end
  end

  scope "/", LeastCostFeedWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{LeastCostFeedWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
