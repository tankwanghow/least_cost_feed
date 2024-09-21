defmodule LeastCostFeedWeb.NutrientLive.Form do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Nutrient
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-1/3 mx-auto">
      <.back navigate={~p"/nutrients"}>Back Nutrient Listing</.back>
      <div class="font-bold text-3xl">
        <%= @page_title %>
      </div>
      <.form for={@form} id="nutrient-form" phx-change="validate" phx-submit="save">
        <div class="mb-2">
          <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="text" label="Unit" />
        </div>

        <.button phx-disable-with="Saving...">Save Nutrient</.button>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    id = params["id"]

    socket =
      case socket.assigns.live_action do
        :new -> mount_new(socket)
        :edit -> mount_edit(socket, id)
      end

    {:ok, socket}
  end

  defp mount_new(socket) do
    nutrient = %Nutrient{}

    socket
    |> assign(action: :new)
    |> assign(id: "new")
    |> assign(page_title: "New Nutrient")
    |> assign(nutrient: nutrient)
    |> assign_new(:form, fn -> to_form(Entities.change_nutrient(nutrient)) end)
  end

  defp mount_edit(socket, id) do
    nutrient = Entities.get_nutrient!(id)

    socket
    |> assign(action: :edit)
    |> assign(id: id)
    |> assign(page_title: "Edit Nutrient")
    |> assign(nutrient: nutrient)
    |> assign_new(:form, fn -> to_form(Entities.change_nutrient(nutrient)) end)
  end

  @impl true
  def handle_event("validate", %{"nutrient" => nutrient_params}, socket) do
    changeset = Entities.change_nutrient(socket.assigns.nutrient, nutrient_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"nutrient" => nutrient_params}, socket) do
    save_nutrient(socket, socket.assigns.action, nutrient_params)
  end

  defp save_nutrient(socket, :edit, nutrient_params) do
    case Entities.update_nutrient(socket.assigns.nutrient, nutrient_params) do
      {:ok, _nutrient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Nutrient updated successfully")
         |> push_navigate(to: ~p"/nutrients")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_nutrient(socket, :new, nutrient_params) do
    case Entities.create_nutrient(nutrient_params) do
      {:ok, _nutrient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Nutrient created successfully")
         |> push_navigate(to: ~p"/nutrients")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
