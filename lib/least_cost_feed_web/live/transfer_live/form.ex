defmodule LeastCostFeedWeb.TransferLive.Form do
  use LeastCostFeedWeb, :live_view
  import Ecto.Query, warn: false

  alias LeastCostFeed.UserAccounts.User
  alias LeastCostFeed.Repo

  alias LeastCostFeed.Entities.{
    Nutrient,
    Ingredient,
    IngredientComposition,
    Formula,
    FormulaIngredient,
    FormulaNutrient,
    FormulaPremixIngredient
  }

  @seed_tables %{
    "User" => ~w(),
    "Nutrient" => ~w(),
    "Ingredient" => ~w(),
    "IngredientComposition" => ~w(),
    "Formula" => ~w(),
    "FormulaIngredient" => ~w(),
    "FormulaNutrient" => ~w(),
    "FormulaPremixIngredient" => ~w()
  }

  @impl true
  def render(assigns) do
    ~H"""
    <.form
      for={%{}}
      id="object-form"
      phx-change="validate"
      phx-submit="start_transfer"
      class="p-4 mb-1 border rounded-lg border-blue-500 bg-blue-200"
    >
      <div class="flex flex-row flex-nowarp mb-2">
        <div class="p-2">Seed</div>
        <.input name="seed_table" value={@seed_table} type="select" options={@seed_tables} />
        <div class="p-2">using</div>

        <div :if={@seed_table != "--Select One--"} class="p-2">
          <.live_file_input upload={@uploads.csv_file} />
        </div>
      </div>

      <.button>
        <%= gettext("Start Seed") %>
      </.button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(seed_tables: Map.keys(@seed_tables))
     |> assign(seed_table: Map.keys(@seed_tables) |> Enum.at(0))
     |> allow_upload(:csv_file,
       accept: ~w(.csv),
       max_file_size: 10_000_000,
       max_entries: 1,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event(
        "start_transfer",
        %{"seed_table" => table},
        socket
      ) do
    consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _ ->
      transfer(table, path)
      {:ok, "Fdsafas"}
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", _, socket) do
    {:noreply, socket}
  end

  defp transfer("FormulaPremixIngredient", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        i = get_ingredient_by_name_email(a.ingredient_name, a.email)
        f = get_formula_by_name_email(a.formula_name, a.email)

        r.insert!(%FormulaPremixIngredient{
          ingredient_id: i.id,
          formula_id: f.id,
          formula_quantity: LeastCostFeedWeb.Helpers.float_parse(a.formula_quantity),
          premix_quantity: LeastCostFeedWeb.Helpers.float_parse(a.premix_quantity)
        })
      end)
    end)
  end

  defp transfer("FormulaNutrient", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        n = get_nutrient_by_name_email(a.nutrient_name, a.email)
        f = get_formula_by_name_email(a.formula_name, a.email)

        r.insert!(%FormulaNutrient{
          nutrient_id: n.id,
          formula_id: f.id,
          min: LeastCostFeedWeb.Helpers.float_parse(a.min),
          max: LeastCostFeedWeb.Helpers.float_parse(a.max),
          actual: LeastCostFeedWeb.Helpers.float_parse(a.actual),
          used: if(a.used == "true", do: true, else: false)
        })
      end)
    end)
  end

  defp transfer("FormulaIngredient", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        i = get_ingredient_by_name_email(a.ingredient_name, a.email)
        f = get_formula_by_name_email(a.formula_name, a.email)

        r.insert!(%FormulaIngredient{
          ingredient_id: i.id,
          formula_id: f.id,
          min: LeastCostFeedWeb.Helpers.float_parse(a.min),
          cost: LeastCostFeedWeb.Helpers.float_parse(a.cost),
          max: LeastCostFeedWeb.Helpers.float_parse(a.max),
          shadow: LeastCostFeedWeb.Helpers.float_parse(a.shadow),
          actual: LeastCostFeedWeb.Helpers.float_parse(a.actual),
          used: if(a.used == "true", do: true, else: false)
        })
      end)
    end)
  end

  defp transfer("Formula", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        u = LeastCostFeed.UserAccounts.get_user_by_email(a.email)

        r.insert!(%Formula{
          user_id: u.id,
          name: a.formula_name,
          batch_size: LeastCostFeedWeb.Helpers.float_parse(a.batch_size),
          weight_unit: a.weight_unit,
          usage_per_day: LeastCostFeedWeb.Helpers.float_parse(a.usage_per_day),
          note: a.note,
          premix_bag_weight: LeastCostFeedWeb.Helpers.float_parse(a.premix_bag_weight),
          premix_bag_usage_qty: String.to_integer(a.premix_bag_usage_qty),
          premix_bags_qty: String.to_integer(a.premix_bags_qty),
          inserted_at: string_to_datetime(a.inserted_at),
          updated_at: string_to_datetime(a.updated_at)
        })
      end)
    end)
  end

  defp transfer("IngredientComposition", path) do
    attrs = csv_to_attrs(path)
      ingcom = attrs
      |> Enum.map(fn a ->
        i = get_ingredient_by_name_email(a.ingredient_name, a.email)
        n = get_nutrient_by_name_email(a.nutrient_name, a.email)
        %{
          ingredient_id: i.id,
          nutrient_id: n.id,
          quantity: LeastCostFeedWeb.Helpers.float_parse(a.quantity)
        }
      end)

      Repo.insert_all(IngredientComposition, ingcom)
  end

  defp transfer("Ingredient", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        u = LeastCostFeed.UserAccounts.get_user_by_email(a.email)

        r.insert!(%Ingredient{
          user_id: u.id,
          name: a.ingredient_name,
          cost: LeastCostFeedWeb.Helpers.float_parse(a.cost),
          category: a.category,
          dry_matter: LeastCostFeedWeb.Helpers.float_parse(a.dry_matter),
          description: a.description,
          inserted_at: string_to_datetime(a.inserted_at),
          updated_at: string_to_datetime(a.updated_at)
        })
      end)
    end)
  end

  defp transfer("Nutrient", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        u = LeastCostFeed.UserAccounts.get_user_by_email(a.email)

        r.insert!(%Nutrient{
          user_id: u.id,
          name: a.nutrient_name,
          unit: a.unit,
          inserted_at: string_to_datetime(a.inserted_at),
          updated_at: string_to_datetime(a.updated_at)
        })
      end)
    end)
  end

  defp transfer("User", path) do
    attrs = csv_to_attrs(path)

    Repo.transaction(fn r ->
      attrs
      |> Enum.each(fn a ->
        r.insert!(%User{
          email: a.email,
          hashed_password: a.hashed_password,
          confirmed_at: string_to_datetime(a.confirmed_at),
          inserted_at: string_to_datetime(a.inserted_at),
          updated_at: string_to_datetime(a.updated_at)
        })
      end)
    end)
  end

  def get_ingredient_by_name_email(name, email) do
    from(i in Ingredient,
      join: u in User,
      on: u.id == i.user_id,
      where: u.email == ^email,
      where: i.name == ^name,
      select: i
    )
    |> Repo.one!()
  end

  def get_nutrient_by_name_email(name, email) do
    from(i in Nutrient,
      join: u in User,
      on: u.id == i.user_id,
      where: u.email == ^email,
      where: i.name == ^name,
      select: i
    )
    |> Repo.one!()
  end

  def get_formula_by_name_email(name, email) do
    from(i in Formula,
      join: u in User,
      on: u.id == i.user_id,
      where: u.email == ^email,
      where: i.name == ^name,
      select: i
    )
    |> Repo.one!()
  end

  defp string_to_datetime(value) do
    Timex.parse!(value, "%Y-%m-%d %H:%M:%S.%f", :strftime)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp csv_to_attrs(path) do
    File.stream!(path)
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      headers, nil ->
        {[], headers}

      row, headers ->
        {[Enum.zip(headers, row) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)], headers}
    end)
    |> Enum.to_list()
  end
end
