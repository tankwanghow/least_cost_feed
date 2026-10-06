defmodule LeastCostFeed.HenModel.Stats do
  @moduledoc """
  Numerical helpers (not model coefficients): normal CDF / inverse CDF and
  the deterministic quantile design used for the virtual-hen population.
  """

  @doc "Standard normal CDF."
  def norm_cdf(x), do: 0.5 * (1.0 + :math.erf(x / :math.sqrt(2.0)))

  @doc """
  Inverse standard normal CDF (Acklam's rational approximation, relative
  error < 1.15e-9). Pure numerics.
  """
  def inv_norm(p) when p > 0.0 and p < 1.0 do
    a = [
      -39.69683028665376,
      220.9460984245205,
      -275.9285104469687,
      138.3577518672690,
      -30.66479806614716,
      2.506628277459239
    ]

    b = [
      -54.47609879822406,
      161.5858368580409,
      -155.6989798598866,
      66.80131188771972,
      -13.28068155288572
    ]

    c = [
      -0.007784894002430293,
      -0.3223964580411365,
      -2.400758277161838,
      -2.549732539343734,
      4.374664141464968,
      2.938163982698783
    ]

    d = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416]
    p_low = 0.02425

    cond do
      p < p_low ->
        q = :math.sqrt(-2.0 * :math.log(p))
        horner(c, q) / (horner(d, q) * q + 1.0)

      p <= 1.0 - p_low ->
        q = p - 0.5
        r = q * q
        horner(a, r) * q / (horner(b, r) * r + 1.0)

      true ->
        q = :math.sqrt(-2.0 * :math.log(1.0 - p))
        -(horner(c, q) / (horner(d, q) * q + 1.0))
    end
  end

  defp horner(coefs, x), do: Enum.reduce(coefs, 0.0, fn k, acc -> acc * x + k end)

  @doc """
  Deterministic population design: `n` pairs `{z, u}` of standard-normal
  scores. `z` uses the exact quantiles `(k - 0.5)/n`; `u` uses the same
  quantiles re-ordered by a golden-ratio (low-discrepancy) sequence, so the
  two are close to uncorrelated. A target correlation `rho` is imposed as
  `u' = rho*z + sqrt(1 - rho^2)*u`. Results are reproducible run to run.
  """
  def population_design(n, rho \\ 0.0) when n > 0 do
    q = for k <- 1..n, do: inv_norm((k - 0.5) / n)
    phi = (:math.sqrt(5.0) - 1.0) / 2.0

    order =
      1..n
      |> Enum.map(fn k -> {k, frac(k * phi)} end)
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.with_index()
      |> Map.new(fn {{k, _}, rank} -> {k, rank} end)

    q_tuple = List.to_tuple(q)
    s = :math.sqrt(max(0.0, 1.0 - rho * rho))

    for k <- 1..n do
      z = elem(q_tuple, k - 1)
      u = elem(q_tuple, Map.fetch!(order, k))
      {z, rho * z + s * u}
    end
  end

  defp frac(x), do: x - Float.floor(x)

  @doc "Linear interpolation over sorted `{x, y}` knots, clamped at both ends."
  def interp([{x0, y0} | _], x) when x <= x0, do: y0

  def interp(knots, x) do
    case Enum.find_index(knots, fn {kx, _} -> kx >= x end) do
      nil ->
        knots |> List.last() |> elem(1)

      i ->
        {x1, y1} = Enum.at(knots, i)
        {x0, y0} = Enum.at(knots, i - 1)
        if x1 == x0, do: y1, else: y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    end
  end
end
