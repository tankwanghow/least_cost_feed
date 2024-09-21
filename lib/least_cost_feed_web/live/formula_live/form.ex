defmodule LeastCostFeedWeb.FormulaLive.Form do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.Formula
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1200px] mx-auto mb-10 p-5">
      <.back navigate={~p"/formulas"}>Back Formula Listing</.back>
      <div class="font-bold text-3xl">
        <%= @page_title %>
      </div>
      <.form for={@form} id="ingredient-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
          <div class="w-[30%]"><.input field={@form[:name]} type="text" label="Name" /></div>
          <div class="w-[10%]">
            <.input field={@form[:weight_unit]} type="text" label="Weight Unit" />
          </div>
          <div class="w-[10%]">
            <.input
              field={@form[:batch_size]}
              type="number"
              label={"Batch Size (#{@form[:weight_unit].value})"}
              step="any"
            />
          </div>
          <div class="w-[10%]">
            <.input
              field={@form[:usage_per_day]}
              type="number"
              label={"Daily Usage (#{@form[:weight_unit].value})"}
              step="any"
            />
          </div>
          <div class="w-[10%]">
            <.input
              field={@form[:cost]}
              type="number"
              label={"Cost per #{@form[:weight_unit].value}"}
              readonly
            />
          </div>
          <div class="w-[30%]"><.input field={@form[:note]} type="text" label="Note" /></div>
        </div>

        <div class="my-2">
          <.button phx-disable-with="Saving...">Save Formula</.button>
          <.link class="blue button">Optimize</.link>
          <.link navigate={~p"/formulas/#{@form[:id].value}/edit"} class="red button">Cancel</.link>
        </div>

        <div class="flex gap-5">
          <div class="w-[65%]">
            <div class="button teal mb-0.5" phx-click="show_select_ingredients">
              Add/Remove Ingredients
            </div>
            <div class="font-bold flex text-center">
              <div class="w-[3%]" />
              <div class="w-[30%]">Ingredient</div>
              <div class="w-[9%]">Cost</div>
              <div class="w-[9%]">Min</div>
              <div class="w-[9%]">Max</div>
              <div class="w-[10%]">Actual</div>
              <div class="w-[10%]">Shadow</div>
              <div class="w-[10%]">Weight</div>
              <div class="w-[10%]">Amount</div>
            </div>
            <div class="h-[720px] overflow-y-auto">
              <.inputs_for :let={nt} field={@form[:formula_ingredients]}>
                <div class={["flex", nt[:delete].value == true && "hidden"]}>
                  <div class="w-[3%] mt-2">
                    <.input type="checkbox" field={nt[:used]} />
                  </div>
                  <div class="w-[30%]">
                    <.input field={nt[:ingredient_name]} readonly />
                  </div>
                  <div class="w-[9%]">
                    <.input type="number" step="any" field={nt[:cost]} />
                  </div>
                  <div class="w-[9%]">
                    <.input type="number" step="any" field={nt[:min]} />
                  </div>
                  <div class="w-[9%]">
                    <.input type="number" step="any" field={nt[:max]} />
                  </div>
                  <div class="w-[10%]">
                    <.input type="number" field={nt[:actual]} readonly />
                  </div>
                  <div class="w-[10%]">
                    <.input type="number" field={nt[:shadow]} readonly />
                  </div>
                  <div class="w-[10%]">
                    <.input
                      type="number"
                      field={nt[:weight]}
                      value={count_weight(@form[:batch_size].value, nt[:actual].value)}
                      readonly
                    />
                  </div>
                  <div class="w-[10%]">
                    <.input
                      type="number"
                      field={nt[:amount]}
                      value={
                        count_amount(@form[:batch_size].value, nt[:actual].value, nt[:cost].value)
                      }
                      readonly
                    />
                  </div>
                  <.input type="hidden" field={nt[:delete]} value={"#{nt[:delete].value}"} />
                  <.input type="hidden" field={nt[:ingredient_id]} />
                </div>
              </.inputs_for>
            </div>
          </div>

          <div class="w-[35%]">
            <div class="button blue mb-0.5" phx-click="show_select_nutrients">
              Add/Remove Nutrients
            </div>
            <div class="font-bold flex text-center">
              <div class="w-[5%]" />
              <div class="w-[35%]">Nutrient</div>
              <div class="w-[20%]">Min</div>
              <div class="w-[20%]">Max</div>
              <div class="w-[20%]">Actual</div>
            </div>
            <div class="h-[720px] overflow-y-auto">
              <.inputs_for :let={nt} field={@form[:formula_nutrients]}>
                <div class={["flex", nt[:delete].value == true && "hidden"]}>
                  <div class="w-[5%] mt-2">
                    <.input type="checkbox" field={nt[:used]} />
                  </div>
                  <div class="w-[35%]">
                    <.input field={nt[:nutrient_name]} readonly />
                  </div>
                  <div class="w-[20%]">
                    <.input type="number" step="any" field={nt[:min]} />
                  </div>
                  <div class="w-[20%]">
                    <.input type="number" step="any" field={nt[:max]} />
                  </div>
                  <div class="w-[20%]">
                    <.input type="number" field={nt[:actual]} readonly />
                  </div>
                  <.input type="hidden" field={nt[:delete]} value={"#{nt[:delete].value}"} />
                  <.input type="hidden" field={nt[:nutrient_id]} />
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

      <.modal
        :if={@show_select_ingredients?}
        id="select-ingredients-modal"
        show
        on_cancel={JS.push("hide_select_ingredients")}
      >
        <.live_component
          id="select_ingredients"
          module={LeastCostFeedWeb.IngredientLive.SelectComponent}
          current_user={@current_user}
          selected_ingredient_ids={@selected_ingredient_ids}
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
     |> assign(show_select_ingredients?: false)
     |> assign(selected_ingredient_ids: selected_ingredients(socket))
     |> assign(selected_nutrient_ids: selected_nutrients(socket))}
  end

  defp mount_new(socket) do
    socket
    |> assign(action: :new)
    |> assign(id: "new")
    |> assign(page_title: "New Formula")
    |> assign_new(:form, fn -> to_form(Entities.change_formula(%Formula{})) end)
  end

  defp mount_edit(socket, id) do
    changeset =
      Entities.change_formula(Entities.get_formula!(id))

    socket
    |> assign(action: :edit)
    |> assign(id: id)
    |> assign(page_title: "Edit Formula")
    |> assign_new(:form, fn ->
      to_form(changeset)
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
  def handle_event("show_select_ingredients", _, socket) do
    {:noreply,
     socket
     |> assign(show_select_ingredients?: true)
     |> assign(selected_ingredient_ids: selected_ingredients(socket))}
  end

  @impl true
  def handle_event("hide_select_ingredients", _, socket) do
    {:noreply, socket |> assign(show_select_ingredients?: false)}
  end

  @impl true
  def handle_event("nutrient_clicked", %{"object-id" => id, "value" => "on"}, socket) do
    nutrient = Entities.get_nutrient!(id)

    new_formual_nutrient = %{
      nutrient_id: nutrient.id,
      nutrient_name: "#{nutrient.name} (#{nutrient.unit})",
      min: 0.0,
      max: 0.0,
      actual: 0.0,
      used: true
    }

    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.add_line(:formula_nutrients, new_formual_nutrient)

    {:noreply, socket |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("nutrient_clicked", %{"object-id" => id}, socket) do
    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.delete_line(id, :formula_nutrients, :nutrient_id)

    {:noreply, socket |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("ingredient_clicked", %{"object-id" => id, "value" => "on"}, socket) do
    ingredient = Entities.get_ingredient!(id)

    new_formula_ingredient = %{
      ingredient_id: ingredient.id,
      ingredient_name: ingredient.name,
      cost: ingredient.cost,
      min: 0.0,
      max: 0.0,
      actual: 9.0,
      shadow: 0.0,
      weight: 0.0,
      amount: 0.0,
      used: true
    }

    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.add_line(:formula_ingredients, new_formula_ingredient)
      |> Formula.refresh_cost()

    {:noreply, socket |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("ingredient_clicked", %{"object-id" => id}, socket) do
    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.delete_line(id, :formula_ingredients, :ingredient_id)
      |> Formula.refresh_cost()

    {:noreply, socket |> assign(form: to_form(cs, action: :validate))}
  end

  @impl true
  def handle_event("validate", %{"formula" => formula_params}, socket) do
    changeset =
      Entities.change_formula(socket.assigns.form.source.data, formula_params)
      |> Formula.refresh_cost()

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"formula" => formula_params}, socket) do
    save_formula(socket, socket.assigns.action, formula_params)
  end

  def selected_nutrients(socket) do
    Ecto.Changeset.get_assoc(socket.assigns.form.source, :formula_nutrients)
    |> Enum.filter(fn x -> !Ecto.Changeset.get_field(x, :delete) end)
    |> Enum.map(fn x -> Ecto.Changeset.get_field(x, :nutrient_id) end)
  end

  def selected_ingredients(socket) do
    Ecto.Changeset.get_assoc(socket.assigns.form.source, :formula_ingredients)
    |> Enum.filter(fn x -> !Ecto.Changeset.get_field(x, :delete) end)
    |> Enum.map(fn x -> Ecto.Changeset.get_field(x, :ingredient_id) end)
  end

  defp save_formula(socket, :edit, formula_params) do
    case Entities.update_formula(socket.assigns.form.source.data, formula_params) do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula updated successfully")
         |> push_navigate(to: ~p"/formulas")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_formula(socket, :new, formula_params) do
    case Entities.create_formula(formula_params) do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula created successfully")
         |> push_navigate(to: ~p"/formulas")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp count_weight(batch_size, actual) do
    bs = LeastCostFeedWeb.Helpers.float_parse(batch_size)
    a = LeastCostFeedWeb.Helpers.float_parse(actual)

    cond do
      a == :error || bs == :error -> -99999.0
      true -> :erlang.float_to_binary(bs * a, [:compact, decimals: 4])
    end
  end

  defp count_amount(batch_size, actual, cost) do
    bs = LeastCostFeedWeb.Helpers.float_parse(batch_size)
    a = LeastCostFeedWeb.Helpers.float_parse(actual)
    c = LeastCostFeedWeb.Helpers.float_parse(cost)

    cond do
      a == :error || bs == :error || c == :error -> -99999.0
      true -> :erlang.float_to_binary(bs * a * c, [:compact, decimals: 4])
    end
  end
end
