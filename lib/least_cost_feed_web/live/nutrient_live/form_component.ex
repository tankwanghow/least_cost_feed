defmodule LeastCostFeedWeb.NutrientLive.FormComponent do
  use LeastCostFeedWeb, :live_component

  alias LeastCostFeed.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage nutrient records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="nutrient-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:unit]} type="text" label="Unit" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Nutrient</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{nutrient: nutrient} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Entities.change_nutrient(nutrient))
     end)}
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
      {:ok, nutrient} ->
        notify_parent({:saved, nutrient})

        {:noreply,
         socket
         |> put_flash(:info, "Nutrient updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_nutrient(socket, :new, nutrient_params) do
    case Entities.create_nutrient(nutrient_params) do
      {:ok, nutrient} ->
        notify_parent({:saved, nutrient})

        {:noreply,
         socket
         |> put_flash(:info, "Nutrient created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
