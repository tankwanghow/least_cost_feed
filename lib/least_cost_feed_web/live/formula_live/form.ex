defmodule LeastCostFeedWeb.FormulaLive.Form do
  use LeastCostFeedWeb, :live_view
  alias Phoenix.PubSub

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.{Formula, FormulaIngredient}
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1200px] mx-auto p-5">
      <.back navigate={~p"/formulas"}>Back Formula Listing</.back>
      <div class="font-bold text-3xl">
        <%= @page_title %>
      </div>
      <.form for={@form} id="formula-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
          <div class="w-[28%]"><.input field={@form[:name]} type="text" label="Name" /></div>
          <div class="w-[9%]">
            <.input field={@form[:weight_unit]} type="text" label="Weight Unit" />
          </div>
          <div class="w-[12%]">
            <.input
              field={@form[:batch_size]}
              type="number"
              label={"Batch Size (#{@form[:weight_unit].value})"}
              step="any"
              value={Helpers.float_decimal(@form[:batch_size].value)}
            />
          </div>
          <div class="w-[12%]">
            <.input
              field={@form[:usage_per_day]}
              type="number"
              label={"Daily Usage (#{@form[:weight_unit].value})"}
              step="any"
              value={Helpers.float_decimal(@form[:usage_per_day].value)}
            />
          </div>
          <div class="w-[12%]">
            <.input
              field={@form[:cost]}
              type="number"
              label={"Cost per 1000#{@form[:weight_unit].value}"}
              readonly
              value={Helpers.float_decimal(@form[:cost].value, 2)}
              tabindex="-1"
            />
          </div>
          <div class="w-[27%]"><.input field={@form[:note]} type="text" label="Note" /></div>
        </div>

        <div class="flex my-2 gap-2">
          <.button phx-disable-with="Saving...">Save Formula</.button>
          <.link
            :if={!@optimizing?}
            class="blue button font-bold w-[30%]"
            phx-click="optimize_formula"
          >
            Try Optimize
          </.link>
          <div :if={@optimizing?} class="hover:cursor-wait gray button font-bold w-[30%]">
            Optimizing....
          </div>
          <.link
            navigate={
              if(@live_action == :new,
                do: ~p"/formulas/new",
                else: ~p"/formulas/#{@form[:id].value}/edit"
              )
            }
            class="red button w-[15%]"
          >
            Cancel
          </.link>
          <.link
            :if={@form.source.changes == %{} and @live_action != :new}
            navigate={~p"/formula_premix/#{@form[:id].value}/edit"}
            class="teal button w-[15%]"
          >
            Premix
          </.link>
          <.link
            :if={@form.source.changes == %{} and @live_action != :new}
            target="_blank"
            navigate={~p"/formulas/print_multi?ids=#{@form[:id].value}"}
            class="blue button w-[15%]"
          >
            Print
          </.link>
        </div>

        <div class="flex gap-5">
          <div class="w-[60%]">
            <div class="font-bold flex text-center">
              <div class="w-[3%]" />
              <div class="w-[32%]">Ingredient</div>
              <div class="w-[11%]">Cost/<%= @form[:weight_unit].value %></div>
              <div class="w-[10%]">Min</div>
              <div class="w-[10%]">Max</div>
              <div class="w-[12%]">Actual</div>
              <div class="w-[12%]">Weight(<%= @form[:weight_unit].value %>)</div>
              <div class="w-[10%]">Shadow</div>
            </div>
            <%!-- h-[580px] overflow-y-auto border bg-teal-200 p-1 rounded-xl border-teal-500 --%>
            <div class="">
              <.inputs_for :let={nt} field={@form[:formula_ingredients]}>
                <div class={["flex", nt[:delete].value == true && "hidden"]}>
                  <div class="w-[3%] mt-2">
                    <.input type="checkbox" field={nt[:used]} tabindex="-1" />
                  </div>
                  <div class="w-[32%]">
                    <.input field={nt[:ingredient_name]} readonly tabindex="-1" />
                  </div>
                  <div class="w-[11%]">
                    <.input
                      type="number"
                      step="any"
                      field={nt[:cost]}
                      value={Helpers.float_decimal(nt[:cost].value)}
                    />
                  </div>
                  <div class="w-[10%]">
                    <.input
                      type="number"
                      step="any"
                      field={nt[:min]}
                      value={Helpers.float_decimal(nt[:min].value, 6)}
                    />
                  </div>
                  <div class="w-[10%]">
                    <.input
                      type="number"
                      step="any"
                      field={nt[:max]}
                      value={Helpers.float_decimal(nt[:max].value, 6)}
                    />
                  </div>
                  <div class="w-[12%]">
                    <.input
                      type="number"
                      field={nt[:actual]}
                      value={Helpers.float_decimal(nt[:actual].value, 6)}
                      tabindex="-1"
                      readonly
                    />
                  </div>
                  <div class="w-[12%]">
                    <.input
                      type="number"
                      field={nt[:weight]}
                      value={count_weight(@form[:batch_size].value, nt[:actual].value)}
                      tabindex="-1"
                      readonly
                    />
                  </div>
                  <div class="w-[10%]">
                    <.input
                      type="number"
                      field={nt[:shadow]}
                      value={Helpers.float_decimal(nt[:shadow].value)}
                      tabindex="-1"
                      readonly
                    />
                  </div>
                  <.input type="hidden" field={nt[:delete]} value={"#{nt[:delete].value}"} />
                  <.input type="hidden" field={nt[:ingredient_id]} />
                </div>
              </.inputs_for>
            </div>
            <div class="button teal mb-0.5 w-[30%] mt-1" phx-click="show_select_ingredients">
              Add/Remove Ingredients
            </div>
          </div>

          <div class="w-[40%]">
            <div class="font-bold flex text-center">
              <div class="w-[4%]" />
              <div class="w-[50%]">Nutrient</div>
              <div class="w-[15%]">Min</div>
              <div class="w-[15%]">Max</div>
              <div class="w-[16%]">Actual</div>
            </div>
            <%!-- h-[580px] overflow-y-auto border bg-sky-200 p-1 rounded-xl border-sky-500--%>
            <div class="">
              <.inputs_for :let={nt} field={@form[:formula_nutrients]}>
                <div class={["flex", nt[:delete].value == true && "hidden"]}>
                  <div class="w-[3%] mt-2 mr-1">
                    <.input type="checkbox" field={nt[:used]} tabindex="-1" />
                  </div>
                  <div class="w-[50%]">
                    <.input
                      field={}
                      name={}
                      value={"#{nt[:nutrient_name].value}(#{nt[:nutrient_unit].value})"}
                      readonly
                      tabindex="-1"
                    />
                  </div>
                  <div class="w-[15%]">
                    <.input type="number" step="any" field={nt[:min]} />
                  </div>
                  <div class="w-[15%]">
                    <.input type="number" step="any" field={nt[:max]} />
                  </div>
                  <div class="w-[17%]">
                    <.input type="number" field={nt[:actual]} readonly tabindex="-1" />
                  </div>
                  <.input type="hidden" field={nt[:delete]} value={"#{nt[:delete].value}"} />
                  <.input type="hidden" field={nt[:nutrient_id]} />
                </div>
              </.inputs_for>
            </div>
            <div class="button blue mb-0.5 w-[40%] mt-1" phx-click="show_select_nutrients">
              Add/Remove Nutrients
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

    if connected?(socket) do
      PubSub.subscribe(
        LeastCostFeed.PubSub,
        "#{socket.assigns.current_user.id}_optimization_job"
      )
    end

    socket =
      case socket.assigns.live_action do
        :new -> mount_new(socket)
        :edit -> mount_edit(socket, id)
        :copy -> mount_copy(socket, id)
      end

    {:ok,
     socket
     |> assign(show_select_nutrients?: false)
     |> assign(show_select_ingredients?: false)
     |> assign(selected_ingredient_ids: selected_ingredients(socket))
     |> assign(selected_nutrient_ids: selected_nutrients(socket))
     |> assign(optimizing?: false)}
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

  defp mount_copy(socket, id) do
    source = Entities.get_formula!(id)

    dest = %Formula{
      name: source.name <> " - COPY",
      weight_unit: source.weight_unit,
      batch_size: source.batch_size,
      usage_per_day: source.usage_per_day,
      target_premix_weight: source.target_premix_weight,
      premix_bag_usage_qty: source.premix_bag_usage_qty,
      premix_bag_make_qty: source.premix_bag_make_qty,
      premix_batch_weight: source.premix_batch_weight,
      formula_ingredients: source.formula_ingredients,
      formula_nutrients: source.formula_nutrients
    }

    socket
    |> assign(action: :new)
    |> assign(live_action: :new)
    |> assign(id: id)
    |> assign(page_title: "Copying Formula")
    |> assign_new(:form, fn ->
      to_form(Entities.change_formula(dest))
    end)
  end

  @impl true
  def handle_info("start_optimize", socket) do
    {:noreply,
     socket |> put_flash(:error, nil) |> put_flash(:info, nil) |> assign(optimizing?: true)}
  end

  @impl true
  def handle_info({"finish_optimize", results}, socket) do
    socket =
      case results do
        {:ok, optimize_ingredient_params, optimize_nutrient_params} ->
          cs =
            Entities.replace_formula_with_optimize(
              socket.assigns.form.source,
              optimize_ingredient_params,
              optimize_nutrient_params
            )
            |> Formula.refresh_cost()

          socket
          |> assign(form: to_form(cs, action: :validate))
          |> put_flash(:info, "Formula OPTIMIZED successfully")
          |> put_flash(:error, nil)

        {:error, title, _msg} ->
          socket |> put_flash(:error, title) |> put_flash(:info, nil)
      end

    {:noreply, socket |> assign(optimizing?: false)}
  end

  @impl true
  def handle_event("optimize_formula", _, socket) do
    PubSub.broadcast(
      LeastCostFeed.PubSub,
      "#{socket.assigns.current_user.id}_optimization_job",
      "start_optimize"
    )

    Task.start(fn ->
      results =
        LeastCostFeed.GlpsolFileGen.optimize(
          socket.assigns.form.source,
          socket.assigns.current_user.id
        )

      PubSub.broadcast(
        LeastCostFeed.PubSub,
        "#{socket.assigns.current_user.id}_optimization_job",
        {"finish_optimize", results}
      )
    end)

    {:noreply, socket}
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

    new_formula_nutrients = %{
      nutrient_id: nutrient.id,
      nutrient_name: "#{nutrient.name}(#{nutrient.unit})",
      min: nil,
      max: nil,
      actual: 0.0,
      used: true
    }

    cs =
      socket.assigns.form.source
      |> LeastCostFeedWeb.Helpers.add_line(:formula_nutrients, new_formula_nutrients)

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

    new_formula_ingredient = %FormulaIngredient{
      ingredient_id: ingredient.id,
      ingredient_name: ingredient.name,
      cost: ingredient.cost,
      min: nil,
      max: nil,
      actual: 0.0,
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

    {:noreply,
     socket
     |> assign(form: to_form(changeset, action: :validate))
     |> put_flash(:error, nil)
     |> put_flash(:info, nil)}
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
      {:ok, formula} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula updated successfully")
         |> push_navigate(to: ~p"/formulas/#{formula.id}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_formula(socket, :new, formula_params) do
    case Entities.create_formula(formula_params) do
      {:ok, formula} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula created successfully")
         |> push_navigate(to: ~p"/formulas/#{formula.id}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp count_weight(batch_size, actual) do
    bs = LeastCostFeedWeb.Helpers.float_parse(batch_size)
    a = LeastCostFeedWeb.Helpers.float_parse(actual)

    cond do
      a == :error || bs == :error -> -99999.0
      true -> LeastCostFeedWeb.Helpers.float_decimal((bs || 0) * (a || 0))
    end
  end
end
