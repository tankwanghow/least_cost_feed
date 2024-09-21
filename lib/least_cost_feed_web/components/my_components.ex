defmodule LeastCostFeedWeb.MyComponents do
  use Phoenix.Component
  import LeastCostFeedWeb.CoreComponents

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"
  attr :end_of_data?, :boolean, default: true
  attr :get_more_data, :string, default: "next-page"
  attr :sort_directions, :atom

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
    attr :h_class, :string
    attr :sort, :any, doc: "the function for handling phx-click event sort on each header col"
    attr :b_class, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column" do
    attr :class, :string
  end

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="flex flex-row font-medium bg-blue-400 text-center border-y border-blue-800 p-2 text-l">
      <div
        :for={col <- @col}
        class={[
          col[:class],
          col[:h_class],
          col[:sort] && "hover:font-extrabold hover:text-white hover:cursor-pointer"
        ]}
        phx-click={col[:sort] && "sort"}
        phx-value-sort-by={col[:sort]}
      >
        <span><%= col[:label] %></span>
        <span :if={@sort_directions[col[:sort]] == :asc}>&uarr;</span>
        <span :if={@sort_directions[col[:sort]] == :desc}>&darr;</span>

      </div>
    </div>

    <div
      id={@id}
      phx-viewport-bottom={!@end_of_data? && @get_more_data}
      phx-page-loading
      phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
    >
      <div
        :for={row <- @rows}
        phx-click={@row_click && @row_click.(row)}
        id={@row_id && @row_id.(row)}
        class={["flex flex-row text-center hover:bg-amber-300 p-1 border-b border-gray-600 bg-amber-200",
        @row_click && "hover:cursor-pointer"]}
      >
        <div :for={{col, _i} <- Enum.with_index(@col)} class={[col[:class], col[:b_class]]}>
          <%= render_slot(col, @row_item.(row)) %>
        </div>

        <div :if={@action != []}>
          <div :for={action <- @action}>
            <div class={action[:class]}>
              <%= render_slot(action, @row_item.(row)) %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:ended, :boolean)

  def infinite_scroll_footer(assigns) do
    ~H"""
    <div :if={@ended} class="mt-2 mb-2 text-center border-y-2 bg-orange-200 border-orange-400 p-2">
      No More.
    </div>

    <div :if={!@ended} class="mt-2 mb-2 text-center border-y-2 bg-blue-200 border-blue-400 p-2">
      Loading...<.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </div>
    """
  end

  attr(:search_val, :any)
  attr(:placeholder, :any)

  def search_form(assigns) do
    ~H"""
    <div class="flex justify-center mb-2">
      <.form for={%{}} id="search-form" phx-change="search" phx-submit="search" autocomplete="off" class="w-full">
        <div class="grid grid-cols-12 gap-1">
          <div class="col-span-11">
            <.input name="search[terms]" type="search" value={@search_val} placeholder={@placeholder} phx-debounce="800"/>
          </div>
          <.button class="col-span-1">🔍</.button>
        </div>
      </.form>
    </div>
    """
  end
end
