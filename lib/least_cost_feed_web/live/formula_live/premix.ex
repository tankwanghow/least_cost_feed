defmodule LeastCostFeedWeb.PremixLive.Form do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeedWeb.Helpers
  alias LeastCostFeed.Entities
  alias LeastCostFeed.Entities.{Formula}
  import Ecto.Query, warn: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-3/4 min-w-[1200px] mx-auto p-5">
      <.back navigate={~p"/formulas/#{@form[:id].value}/edit"}>Back Formula</.back>
      <div class="font-bold text-3xl">
        <%= @page_title %>
      </div>
      <.form for={@form} id="premix-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <.input field={@form[:user_id]} type="hidden" value={@current_user.id} />
          <div class="w-[20%]"><.input field={@form[:name]} type="text" label="Name" readonly /></div>
          <div class="w-[10%]">
            <.input
              field={@form[:target_premix_weight]}
              type="number"
              label={"Target Weight(#{@form[:weight_unit].value})"}
              step="any"
              value={Helpers.float_decimal(@form[:target_premix_weight].value)}
            />
          </div>
          <div class="w-[8%]">
            <.input
              field={@form[:left_premix_bag_weight]}
              type="number"
              label={"Still need(#{@form[:weight_unit].value})"}
              step="any"
              value={Helpers.float_decimal(@form[:left_premix_bag_weight].value)}
              readonly
            />
          </div>

          <div class="w-[10%]">
            <.input
              field={@form[:premix_bag_usage_qty]}
              type="number"
              label="Bag use in Formula"
              step="any"
            />
          </div>
          <div class="w-[8%]">
            <.input field={@form[:premix_bag_make_qty]} type="number" label="Bags to Make" />
          </div>

          <div class="w-[12%] font-bold">
            <.input
              field={@form[:true_premix_bag_weight]}
              type="number"
              label={"Premix Bag Weight(#{@form[:weight_unit].value})"}
              value={Helpers.float_decimal(@form[:true_premix_bag_weight].value)}
              readonly
            />
          </div>

          <div class="w-[13%] font-bold">
            <.input
              field={@form[:premix_batch_weight]}
              type="number"
              label={"Premix Batch Weight(#{@form[:weight_unit].value})"}
              value={Helpers.float_decimal(@form[:premix_batch_weight].value)}
              readonly
            />
          </div>
        </div>

        <div class="flex my-2 gap-2">
          <.button phx-disable-with="Saving...">Save Premix</.button>
          <.link
            :if={@form.source.changes != %{}}
            navigate={~p"/formula_premix/#{@form[:id].value}/edit"}
            class="red button"
          >
            Cancel
          </.link>
          <.link
            :if={@form.source.changes == %{} and @live_action != :new}
            target="_blank"
            navigate={~p"/formulas_premix/print_multi?ids=#{@form[:id].value}"}
            class="blue button w-[15%]"
          >
            Print
          </.link>
        </div>

        <div class="flex gap-5">
          <div class="w-[65%]">
            <div class="font-bold flex text-center">
              <div class="w-[30%]">Ingredient</div>
              <div class="w-[20%]">Formual Needed</div>
              <div class="w-[20%]">Premix Provided</div>
            </div>
            <%!-- h-[580px] overflow-y-auto border bg-teal-200 p-1 rounded-xl border-teal-500 --%>
            <div class="">
              <.inputs_for :let={nt} field={@form[:formula_premix_ingredients]}>
                <div class={["flex", nt[:delete].value == true && "hidden"]}>
                  <div class="w-[30%]">
                    <.input field={nt[:ingredient_name]} readonly />
                  </div>
                  <div class={[
                    "w-[20%]",
                    Helpers.float_parse(nt[:formula_quantity].value) !=
                      Helpers.float_parse(nt[:premix_quantity].value) && "font-bold"
                  ]}>
                    <.input
                      type="number"
                      field={nt[:formula_quantity]}
                      value={Helpers.float_decimal(nt[:formula_quantity].value)}
                      readonly
                    />
                  </div>
                  <div class={["w-[20%]"]}>
                    <.input
                      type="number"
                      field={nt[:premix_quantity]}
                      value={Helpers.float_decimal(nt[:premix_quantity].value)}
                      step="any"
                    />
                  </div>
                  <.input type="hidden" field={nt[:ingredient_id]} />
                  <.input type="hidden" field={nt[:formula_id]} />
                  <.input type="hidden" field={nt[:delete]} value={"#{nt[:delete].value}"} />
                </div>
              </.inputs_for>
            </div>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    id = params["id"]

    formula = Entities.get_formula_premix_ingredients!(id)
    changeset = Entities.change_formula_premix(formula)

    fpings = Ecto.Changeset.get_assoc(changeset, :formula_premix_ingredients)

    fings = Entities.get_formula_ingredients!(id)

    fpings =
      fpings
      |> Enum.map(fn fping ->
        fing =
          fings
          |> Enum.find(fn fi ->
            fi.ingredient_id == LeastCostFeed.Helpers.my_fetch_field!(fping, :ingredient_id)
          end)

        if fing do
          if(
            fing.formula_quantity !=
              LeastCostFeed.Helpers.my_fetch_field!(fping, :formula_quantity)
          ) do
            Ecto.Changeset.change(fping, formula_quantity: Float.round(fing.formula_quantity, 6))
          else
            fping
          end
        else
          Ecto.Changeset.change(fping, delete: true)
        end
      end)

    new =
      fings
      |> Enum.map(fn x ->
        index =
          Enum.find_index(fpings, fn fp ->
            x.ingredient_id == LeastCostFeed.Helpers.my_fetch_field!(fp, :ingredient_id)
          end)

        if is_nil(index), do: x
      end)
      |> Enum.filter(fn x -> !is_nil(x) end)

    changeset =
      changeset
      |> Ecto.Changeset.put_assoc(
        :formula_premix_ingredients,
        (fpings ++ new)
        |> Enum.sort_by(&LeastCostFeed.Helpers.my_fetch_field!(&1, :formula_quantity), :desc)
      )

    # |> Formula.refresh_premix_calculations()

    {:ok,
     socket
     |> assign(action: :edit)
     |> assign(id: id)
     |> assign(page_title: "Edit Premix")
     |> assign_new(:form, fn -> to_form(changeset) end)}
  end

  @impl true
  def handle_event("validate", %{"formula" => formula_params}, socket) do
    changeset =
      Entities.change_formula_premix(socket.assigns.form.source.data, formula_params)
      |> Formula.refresh_premix_calculations()

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

  defp save_formula(socket, :edit, formula_params) do
    case Entities.update_formula_premix(socket.assigns.form.source.data, formula_params) do
      {:ok, formula} ->
        {:noreply,
         socket
         |> put_flash(:info, "Formula Premix updated successfully")
         |> push_navigate(to: ~p"/formula_premix/#{formula.id}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
