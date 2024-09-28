defmodule LeastCostFeedWeb.FormulaLive.FormulaPrint do
  use LeastCostFeedWeb, :live_view

  alias LeastCostFeed.Entities

  @impl true
  def mount(%{"ids" => ids}, _, socket) do
    ids = String.split(ids, ",")

    {:ok,
     socket
     |> assign(page_title: gettext("Print"))
     |> set_page_defaults()
     |> fill_formulas(ids)}
  end

  defp set_page_defaults(socket) do
    socket
  end

  defp fill_formulas(socket, ids) do
    formulas =
      Entities.get_print_formulas!(ids)

    socket
    |> assign(:formulas, formulas)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="print-me" class="print-here">
      <%= pre_print_style(assigns) %>
      <%= full_style(assigns) %>
      <%= for formula  <- @formulas do %>
        <div class="page">
          <div class="">
            <%= letter_head(formula, assigns) %>
          </div>
          <%= formula_header(formula, assigns) %>

          <div class="border p-4 border-black leading-[21px] rounded">
            <div class="flex font-bold border-b border-black">
              <div class="w-[40%] ">Ingredient</div>
              <div class="w-[15%] text-right">Cost/<%= formula.weight_unit %></div>
              <div class="w-[15%] text-right">%</div>
              <div class="w-[15%] text-right"><%= formula.weight_unit %></div>
              <div class="w-[15%] text-right">Amount</div>
            </div>
            <%= for dtl <- formula.formula_ingredients do %>
              <div :if={dtl.actual > 0.0} class="flex">
                <%= ingredient(dtl, formula, assigns) %>
              </div>
            <% end %>
          </div>

          <div class="border p-4 border-black leading-[21px] rounded mt-2">
            <div class="flex font-bold border-b border-black">
              <div class="w-[50%] text-center">Nutrient</div>
              <div class="w-[50%] text-center">Actual</div>
            </div>
            <%= for dtl <- formula.formula_nutrients do %>
              <div :if={dtl.actual > 0.0} class="flex">
                <%= nutrient(dtl, assigns) %>
              </div>
            <% end %>
          </div>

          <%!-- <%= formula_footer(formula, assigns) %> --%>
          <div class="">
            <%= letter_foot(formula, assigns) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def ingredient(i, f, assigns) do
    assigns = assign(assigns, :i, i) |> assign(:f, f)

    ~H"""
    <div class="w-[40%] text-nowrap overflow-hidden"><%= @i.ingredient_name %></div>
    <div class="w-[15%] text-right">
      <%= Number.Delimit.number_to_delimited(@i.cost, precision: 4) %>
    </div>
    <div class="w-[15%] text-right">
      <%= Number.Delimit.number_to_delimited(@i.actual * 100, precision: 2) %>%
    </div>
    <div class="w-[15%] text-right">
      <%= Number.Delimit.number_to_delimited(@i.actual * @f.batch_size, precision: 2) %>
    </div>
    <div class="w-[15%] text-right">
      <%= Number.Delimit.number_to_delimited(@i.actual * @f.batch_size * @i.cost, precision: 2) %>
    </div>
    """
  end

  def nutrient(n, assigns) do
    assigns = assign(assigns, :n, n)

    ~H"""
    <div class="w-[50%] text-center"><%= @n.nutrient_name %></div>
    <div class="w-[50%] text-center">
      <%= Number.Delimit.number_to_delimited(@n.actual) %> <%= @n.nutrient_unit %>
    </div>
    """
  end

  def letter_head(formula, assigns) do
    assigns = assigns |> assign(:formula, formula)

    ~H"""
    <div class="text-sm text-gray-400">
      Formula optimized by LeastCostFeed (<%= @formula.updated_at %>)
    </div>
    """
  end

  def letter_foot(formula, assigns) do
    assigns = assigns |> assign(:formula, formula)

    ~H"""
    <div class="text-sm text-gray-400">
      Formula optimized by LeastCostFeed (<%= @formula.updated_at %>)
    </div>
    """
  end

  def formula_header(formula, assigns) do
    assigns = assigns |> assign(:formula, formula)

    ~H"""
    <div class="font-bold text-2xl"><%= @formula.name %></div>
    <div class="flex gap-6">
      <div class="font-bold text-xl">
        <span class="text-xl font-normal">Batch Size:</span>
        <%= "#{Number.Delimit.number_to_delimited(@formula.batch_size)}#{@formula.weight_unit}" %>
      </div>

      <div class="font-bold text-xl">
        <span class="text-xl font-normal">Cost:</span>
        <%= "#{Number.Delimit.number_to_delimited(@formula.cost)}/1000#{@formula.weight_unit}" %>
      </div>
    </div>
    """
  end

  def formula_footer(formula, assigns) do
    assigns = assigns |> assign(:formula, formula)

    ~H"""
    """
  end

  def full_style(assigns) do
    ~H"""
    <style>
    </style>
    """
  end

  def pre_print_style(assigns) do
    ~H"""
    <style>
      .page { width: 210mm; min-height: 290mm; padding: 5mm; }

      @media print {
        @page { size: A4; margin: 0mm; }
        body { width: 210mm; height: 290mm; margin: 0mm; }
        html { margin: 0mm; }
        .page { padding: 5mm; page-break-after: always;} }
    </style>
    """
  end
end
