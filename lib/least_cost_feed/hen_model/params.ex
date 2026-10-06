defmodule LeastCostFeed.HenModel.Params do
  @moduledoc """
  Every coefficient used by the hen model, loaded at compile time from
  `priv/hen_model/parameters.csv` (see `priv/hen_model/sources.md`).

  Each parameter keeps its `status`:

    * `:sourced`     - value as printed in a cited source
    * `:derived`     - arithmetic on sourced numbers (see `priv/hen_model/derive.py`
                       and `test/least_cost_feed/hen_model/params_test.exs`)
    * `:assumed`     - design/biological assumption with no direct source
    * `:placeholder` - value needed but not yet known; neutral default

  so the UI can flag assumed/placeholder values. Code must read numbers via
  `value/2` (never hard-code a coefficient).
  """

  alias LeastCostFeed.HenModel.CSV

  @file_name "parameters.csv"
  @external_resource CSV.path(@file_name)

  @rows CSV.read!(@file_name)

  @params @rows
          |> Enum.map(fn r ->
            {r["param_id"],
             %{
               id: r["param_id"],
               group: r["group"],
               description: r["description"],
               raw: r["value"],
               value: CSV.to_float(r["value"]),
               unit: r["unit"],
               source_id: r["source_id"],
               location: r["location_in_source"],
               status: r["status"] |> String.downcase() |> String.to_atom(),
               notes: r["notes"]
             }}
          end)
          |> Map.new()

  @order Enum.map(@rows, & &1["param_id"])

  # PLACEHOLDER rows whose CSV value is blank: the neutral ("off") default the
  # parameter notes call for. Nothing else may be defaulted in code.
  @neutral_defaults %{"heat_lay_slope" => 0.0, "intake_cap_heat" => 0.0}

  @doc "All parameters in CSV order."
  def all, do: Enum.map(@order, &Map.fetch!(@params, &1))

  @doc "Parameter metadata map, or raises."
  def get!(id), do: Map.fetch!(@params, id)

  def get(id), do: Map.get(@params, id)

  def status(id), do: get!(id).status

  @doc """
  Numeric value of a parameter, honouring `overrides` (a map of id => number,
  e.g. user inputs or calibration). Raises if the parameter does not exist or
  has no numeric value and no neutral default.
  """
  def value(id, overrides \\ %{}) do
    case Map.fetch(overrides, id) do
      {:ok, v} when is_number(v) ->
        v * 1.0

      _ ->
        p = get!(id)

        cond do
          is_number(p.value) ->
            p.value

          Map.has_key?(@neutral_defaults, id) ->
            Map.fetch!(@neutral_defaults, id)

          true ->
            raise ArgumentError,
                  "hen model parameter #{id} has no numeric value (#{inspect(p.raw)})"
        end
    end
  end

  @doc "Numeric value or nil (for optional inputs such as `egg_price_per_kg`)."
  def value_or_nil(id, overrides \\ %{}) do
    case Map.fetch(overrides, id) do
      {:ok, v} when is_number(v) -> v * 1.0
      _ -> get!(id).value
    end
  end

  @doc "Parameters whose status is ASSUMED or PLACEHOLDER (shown in the UI's assumptions panel)."
  def flagged, do: Enum.filter(all(), &(&1.status in [:assumed, :placeholder]))

  @doc "Status counts, e.g. %{sourced: 75, derived: 37, ...}."
  def status_counts, do: Enum.frequencies_by(all(), & &1.status)
end
