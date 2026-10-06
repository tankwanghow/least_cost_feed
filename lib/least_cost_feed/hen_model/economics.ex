defmodule LeastCostFeed.HenModel.Economics do
  @moduledoc """
  Feed cost, egg revenue and margin per hen-day (SPEC 4.10).

    * feed price per kg = LCF `formula.cost / 1000` unless overridden
    * `:per_kg` revenue = lay/100 × EW/1000 × price per kg (v1 default)
    * `:per_egg` revenue = lay/100 × Σ_g price_g × P(EW_ind ∈ band_g),
      `EW_ind ~ N(EW, geno_egg_wt_sd)`. Grade bands are user inputs
      (`egg_grade_bands` is PLACEHOLDER: no default bands are shipped).
  """

  alias LeastCostFeed.HenModel.{Params, Stats}

  def feed_cost_hd(fi_g, price_per_kg) when is_number(price_per_kg),
    do: fi_g / 1000.0 * price_per_kg

  def feed_cost_hd(_fi, _), do: nil

  @doc "Egg revenue per hen-day. `pricing`: `{:per_kg, price}` or `{:per_egg, bands}`."
  def revenue_hd(lay, ew, pricing, ov \\ %{})

  def revenue_hd(lay, ew, {:per_kg, price}, _ov) when is_number(price),
    do: lay / 100.0 * ew / 1000.0 * price

  def revenue_hd(lay, ew, {:per_egg, [_ | _] = bands}, ov) do
    sd = Params.value("geno_egg_wt_sd", ov)

    lay / 100.0 *
      (bands
       |> Enum.zip(grade_shares(ew, sd, bands))
       |> Enum.map(fn {b, s} -> b.price * s end)
       |> Enum.sum())
  end

  def revenue_hd(_, _, _, _), do: nil

  @doc "Share of eggs in each band `%{min, max}` (nil = open) for mean EW and SD."
  def grade_shares(ew, sd, bands) do
    Enum.map(bands, fn b ->
      hi = if b[:max], do: Stats.norm_cdf((b.max - ew) / sd), else: 1.0
      lo = if b[:min], do: Stats.norm_cdf((b.min - ew) / sd), else: 0.0
      max(hi - lo, 0.0)
    end)
  end

  @doc """
  Parses grade bands typed as lines `name,min_g,max_g,price_per_egg`
  (blank min/max = open). Returns `{:ok, bands}` or `{:error, msg}`.
  """
  def parse_bands(text) do
    text
    |> String.split(["\n", ";"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case String.split(line, ",") |> Enum.map(&String.trim/1) do
        [name, mn, mx, price] ->
          with {:ok, p} <- num(price), {:ok, a} <- opt(mn), {:ok, b} <- opt(mx) do
            {:cont, {:ok, [%{name: name, min: a, max: b, price: p} | acc]}}
          else
            _ -> {:halt, {:error, "Cannot read band line: #{line}"}}
          end

        _ ->
          {:halt, {:error, "Band lines must be name,min_g,max_g,price: #{line}"}}
      end
    end)
    |> case do
      {:ok, bands} -> {:ok, Enum.reverse(bands)}
      err -> err
    end
  end

  defp opt(""), do: {:ok, nil}
  defp opt(s), do: num(s)

  defp num(s) do
    case Float.parse(s) do
      {f, ""} -> {:ok, f}
      _ -> :error
    end
  end
end
