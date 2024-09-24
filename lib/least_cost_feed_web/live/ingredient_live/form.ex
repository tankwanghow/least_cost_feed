defmodule LeastCostFeedWeb.IngredientLive.Form do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Ingredient
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-2/3 mx-auto mb-10">
      <.back navigate={~p"/ingredients"}>Back Ingredient Listing</.back>
      <div class="font-bold text-3xl">
        <%= @page_title %>
      </div>
      <.form for={@form} id="ingredient-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-10">
          <div class="w-[50%]">
            <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
            <.input field={@form[:name]} type="text" label="Name" />
            <.input field={@form[:category]} type="text" label="Category" />
            <.input
              field={@form[:cost]}
              type="number"
              label="Cost"
              step="any"
              value={LeastCostFeedWeb.Helpers.float_decimal(@form[:cost].value)}
            />
            <span
              :if={@live_action == :edit and Ecto.Changeset.changed?(@form.source, :cost)}
              class="text-amber-700 font-bold"
            >
              Waring!! changing the COST here, will effect COST in all Formulas.
              <p class="text-sm text-green-600">
                You can change COST in Formula, which will NOT effect others Formulas.
              </p>
            </span>
            <.input field={@form[:dry_matter]} type="number" label="Dry Matter %" step="any" />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <div class="mt-4">
              <.button phx-disable-with="Saving...">Save Ingredient</.button>
            </div>
          </div>
          <div class="w-[50%] -mt-11">
            <div class="button blue mb-0.5" phx-click="show_select_nutrients">
              Add/Remove Nutrients
            </div>
            <div class="font-bold flex">
              <div class="w-[50%]">Nutrient</div>
              <div class="w-[30%]">Quantity</div>
              <div class="w-[20%]">Unit</div>
            </div>
            <div class="h-[720px] overflow-y-auto">
              <.inputs_for :let={ing_com} field={@form[:ingredient_compositions]}>
                <div class={["flex", ing_com[:delete].value == true && "hidden"]}>
                  <div class="w-[50%]">
                    <.input field={ing_com[:nutrient_name]} readonly />
                  </div>
                  <div class="w-[30%]">
                    <.input
                      type="number"
                      step="any"
                      field={ing_com[:quantity]}
                      value={LeastCostFeedWeb.Helpers.float_decimal(ing_com[:quantity].value)}
                    />
                  </div>
                  <div class="w-[20%]">
                    <.input field={ing_com[:nutrient_unit]} readonly />
                  </div>
                  <.input type="hidden" field={ing_com[:delete]} value={"#{ing_com[:delete].value}"} />
                  <.input type="hidden" field={ing_com[:nutrient_id]} />
                </div>
              </.inputs_for>
            </div>
          </div>
        </div>
      </.form>

      <.modal
        :if={@show_select_nutrients?}
        id="select-nutrients-modal"
        show
        on_cancel={JS.push("hide_select_nutrients")}
      >
        <.live_component
          id="select_nutrients"
          module={LeastCostFeedWeb.NutrientLive.SelectComponent}
          current_user={@current_user}
          selected_nutrient_ids={@selected_nutrient_ids}
        />
      </.modal>
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

    {:ok,
     socket
     |> assign(show_select_nutrients?: false)
     |> assign(selected_nutrient_ids: selected_nutrients(socket))}
  end

  defp mount_new(socket) do
    socket
    |> assign(action: :new)
    |> assign(id: "new")
    |> assign(page_title: "New Ingredient")
    |> assign_new(:form, fn -> to_form(Entities.change_ingredient(%Ingredient{})) end)
  end

  defp mount_edit(socket, id) do
    socket
    |> assign(action: :edit)
    |> assign(id: id)
    |> assign(page_title: "Edit Ingredient")
    |> assign_new(:form, fn ->
      to_form(Entities.change_ingredient(Entities.get_ingredient!(id)))
    end)
  end

  @impl true
  def handle_event("show_select_nutrients", _, socket) do
    {:noreply,
     socket
     |> assign(show_select_nutrients?: true)
     |> assign(selected_nutrient_ids: selected_nutrients(socket))}
  end

  @impl true
  def handle_event("hide_select_nutrients", _, socket) do
    {:noreply, socket |> assign(show_select_nutrients?: false)}
  end

  @impl true
  def handle_event("nutrient_clicked", %{"object-id" => id, "value" => "on"}, socket) do
    nutrient = Entities.get_nutrient!(id)

    new_ingredient_composition = %{
      nutrient_id: nutrient.id,
      nutrient_name: nutrient.name,
      nutrient_unit: nutrient.unit,
      quantity: 0.0
    }

    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.add_line(:ingredient_compositions, new_ingredient_composition)

    {:noreply,
     socket
     |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("nutrient_clicked", %{"object-id" => id}, socket) do
    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.delete_line(id, :ingredient_compositions, :nutrient_id)

    {:noreply,
     socket
     |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("validate", %{"ingredient" => ingredient_params}, socket) do
    changeset = Entities.change_ingredient(socket.assigns.form.source.data, ingredient_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"ingredient" => ingredient_params}, socket) do
    save_ingredient(socket, socket.assigns.action, ingredient_params)
  end

  def selected_nutrients(socket) do
    Ecto.Changeset.get_assoc(socket.assigns.form.source, :ingredient_compositions)
    |> Enum.filter(fn x -> !Ecto.Changeset.get_field(x, :delete) end)
    |> Enum.map(fn x -> Ecto.Changeset.get_field(x, :nutrient_id) end)
  end

  defp save_ingredient(socket, :edit, ingredient_params) do
    case Entities.update_ingredient(socket.assigns.form.source.data, ingredient_params) do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingredient updated successfully")
         |> push_navigate(to: ~p"/ingredients")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_ingredient(socket, :new, ingredient_params) do
    case Entities.create_ingredient(ingredient_params) do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingredient created successfully")
         |> push_navigate(to: ~p"/ingredients")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
