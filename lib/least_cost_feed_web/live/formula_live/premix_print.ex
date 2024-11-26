defmodule LeastCostFeedWeb.FormulaLive.PremixPrint do
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
      Entities.get_print_premix!(ids)

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
          <div class="border p-4 border-black leading-[27px] rounded mb-6 text-xl">
            <div class="flex font-bold border-b border-black">
              <div class="w-[50%] ">Ingredient</div>
              <div class="w-[25%] text-right">%</div>
              <div class="w-[25%] text-right"><%= formula.weight_unit %></div>
            </div>
            <%= for dtl <- formula.formula_premix_ingredients do %>
              <%= ingredient(dtl, formula, assigns) %>
            <% end %>
            <%= premix_item(formula, assigns) %>
          </div>

          <%= premix_header(formula, assigns) %>
          <div class="border p-4 border-black leading-[27px] rounded text-xl">
            <div class="flex font-bold border-b border-black">
              <div class="w-[50%] ">Ingredient</div>
              <div class="w-[25%] text-right">%</div>
              <div class="w-[25%] text-right"><%= formula.weight_unit %></div>
            </div>
            <%= for dtl <- formula.formula_premix_ingredients do %>
              <%= premix_ingredient(dtl, formula, assigns) %>
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

  def premix_ingredient(i, f, assigns) do
    assigns = assign(assigns, :i, i) |> assign(:f, f)

    true_premix_bag_weight =
      f.premix_batch_weight / f.premix_bag_make_qty * f.premix_bag_usage_qty

    p = i.premix_quantity / true_premix_bag_weight

    assigns = assign(assigns, :precentage, p)

    ~H"""
    <div :if={@precentage > 0} class="flex">
      <div class="w-[50%] text-nowrap overflow-hidden"><%= @i.ingredient_name %></div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(@precentage * 100, precision: 2) %>%
      </div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(@precentage * @f.premix_batch_weight, precision: 2) %>
      </div>
    </div>
    """
  end

  def premix_item(f, assigns) do
    assigns = assign(assigns, :f, f)

    ~H"""
    <div class="flex">
      <div class="w-[50%] text-nowrap overflow-hidden"><%= @f.name %>**PREMIX**</div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(
          @f.premix_batch_weight / @f.premix_bag_make_qty * @f.premix_bag_usage_qty / @f.batch_size *
            100,
          precision: 2
        ) %>%
      </div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(
          @f.premix_batch_weight /
            @f.premix_bag_make_qty * @f.premix_bag_usage_qty,
          precision: 2
        ) %>
      </div>
    </div>
    """
  end

  def ingredient(i, f, assigns) do
    assigns = assign(assigns, :i, i) |> assign(:f, f)

    ~H"""
    <div :if={@i.formula_quantity - @i.premix_quantity > 0.0} class="flex">
      <div class="w-[50%] text-nowrap overflow-hidden"><%= @i.ingredient_name %></div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(
          (@i.formula_quantity - @i.premix_quantity) / @f.batch_size * 100,
          precision: 2
        ) %>%
      </div>
      <div class="w-[25%] text-right">
        <%= Number.Delimit.number_to_delimited(@i.formula_quantity - @i.premix_quantity, precision: 2) %>
      </div>
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
    <div class="font-bold text-3xl"><%= @formula.name %></div>
    <div class="flex gap-6">
      <div class="font-bold text-2xl">
        <span class="text-xl font-normal">Batch Size:</span>
        <%= "#{Number.Delimit.number_to_delimited(@formula.batch_size)}#{@formula.weight_unit}" %>
      </div>
    </div>
    """
  end

  def premix_header(formula, assigns) do
    assigns = assigns |> assign(:f, formula)

    ~H"""
    <div class="font-bold text-3xl"><%= @f.name %>**PREMIX**</div>
    <div class="flex gap-6">
      <div class="font-bold text-2xl">
        <span class="text-xl font-normal">Bag Weight:</span>
        <%= "#{Number.Delimit.number_to_delimited(@f.premix_batch_weight / @f.premix_bag_make_qty)}#{@f.weight_unit}" %>
      </div>

      <div class="font-bold text-2xl">
        <span class="text-xl font-normal">Bag Make:</span>
        <%= "#{@f.premix_bag_make_qty}" %>
      </div>

      <div class="font-bold text-2xl">
        <span class="text-xl font-normal">Batch Size:</span>
        <%= "#{Number.Delimit.number_to_delimited(@f.premix_batch_weight)}#{@f.weight_unit}" %>
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
      .page { width: 210mm; min-height: 290mm; padding: 5mm;}

        @media print {
          @page { size: A4; margin: 0mm; }
          body { width: 210mm; height: 290mm; margin: 0mm; }
          html { margin: 0mm; }
          .page { padding-top: 0; padding-bottom: 0; padding-left: 10mm; padding-right: 10mm; page-break-after: always; } }
    </style>
    """
  end
end
