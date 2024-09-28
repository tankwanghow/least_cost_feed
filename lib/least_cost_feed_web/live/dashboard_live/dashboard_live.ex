defmodule LeastCostFeedWeb.DashboardLive do
  use LeastCostFeedWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
    <%!-- <div class="font-medium text-xl">Accounting</div> --%>
    <div class="mb-4 gap-1 flex flex-wrap justify-center">
      <.link navigate={~p"/nutrients"} class="button blue">
        Nutrients
      </.link>
      <.link navigate={~p"/ingredients"} class="button blue">
        Ingredients
      </.link>
      <.link navigate={~p"/formulas"} class="button blue">
        Formulas
      </.link>
      <.link navigate={~p"/ingredient_usages"} class="button blue">
        Ingredient Usages
      </.link>
      <.link :if={@current_user.is_admin} navigate={~p"/transfer"} class="button blue">
        Transfer for Ruby LCF
      </.link>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:back_to_route, "#") |> assign(page_title: "Dashboard")}
  end
end
