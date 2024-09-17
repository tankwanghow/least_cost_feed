defmodule LeastCostFeedWeb.NutrientLive.Index do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Nutrient
  import Ecto.Query, warn: false

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(search: %{terms: ""}) |> filter("", false, 1)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Nutrient")
    |> assign(:nutrient, Entities.get_nutrient!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Nutrient")
    |> assign(:nutrient, %Nutrient{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Nutrients")
    |> assign(:nutrient, nil)
  end

  @impl true
  def handle_info({LeastCostFeedWeb.NutrientLive.FormComponent, {:saved, nutrient}}, socket) do
    {:noreply, stream_insert(socket, :nutrients, nutrient)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    nutrient = Entities.get_nutrient!(id)
    {:ok, _} = Entities.delete_nutrient(nutrient)

    {:noreply, stream_delete(socket, :nutrients, nutrient)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"terms" => terms}}, socket) do
    {:noreply, socket |> filter(terms, true, 1)}
  end

  @impl true
  def handle_event("next-page", _, socket) do
    {:noreply, socket |> filter("", false, socket.assigns.page + 1)}
  end

  defp filter(socket, terms, reset, page) do
    query =
      Ecto.Query.from(nt in Nutrient,
        where: nt.user_id == ^socket.assigns.current_user.id,
        where: ilike(nt.name, ^"%#{terms}%")
      )

    objects =
      Entities.list_entities(query, page: page, per_page: @per_page)

    obj_count = Enum.count(objects)

    socket
    |> assign(page: page, per_page: @per_page)
    |> stream(:nutrients, objects, reset: reset)
    |> assign(end_of_timeline?: obj_count < @per_page)
  end
end
