defmodule LeastCostFeed.HenModel.AminoAcids do
  @moduledoc """
  SID amino-acid requirement of a hen (SPEC 4.3, Reading form):

      R_i = a_scalar * a_i * E + m_i * W^0.75        (mg SID/d)

  * `m_i` maintenance, set A (default; S14/S15, broiler-breeder pullets) or
    set B (S13; M+C and Thr only, others fall back to set A).
  * `a_i` per g egg output, DERIVED so that R_i equals the Hendrix Layer-2
    SID requirement (S4 Table 3).
  * `a_scalar` = `cal_aa_a_scalar` (PLACEHOLDER calibration handle, 1.0).
  """

  alias LeastCostFeed.HenModel.Params

  @aas [:lys, :met, :metcys, :thr, :trp, :val, :ile, :arg]
  @labels %{
    lys: "Lys",
    met: "Met",
    metcys: "Met+Cys",
    thr: "Thr",
    trp: "Trp",
    val: "Val",
    ile: "Ile",
    arg: "Arg"
  }

  def aas, do: @aas
  def label(aa), do: Map.get(@labels, aa, aa |> to_string() |> String.capitalize())

  @doc "Coefficients `%{aa => %{a: mg/g egg, m: mg/kg^0.75/d}}` for maintenance set `:a` or `:b`."
  def coefficients(set \\ :a, ov \\ %{}) do
    a_scalar = Params.value("cal_aa_a_scalar", ov)

    Map.new(@aas, fn aa ->
      {m_id, a_id} =
        if set == :b and aa in [:metcys, :thr],
          do: {"maint_#{aa}_setB", "egg_coef_#{aa}_setB"},
          else: {"maint_#{aa}", "egg_coef_#{aa}"}

      {aa, %{a: a_scalar * Params.value(a_id, ov), m: Params.value(m_id, ov)}}
    end)
  end

  @doc "Requirement map `%{aa => mg/d}` for egg output `e` (g/d) and BW `w` (kg)."
  def requirement(coefs, e, w) do
    w75 = :math.pow(w, 0.75)
    Map.new(coefs, fn {aa, %{a: a, m: m}} -> {aa, a * e + m * w75} end)
  end

  @doc """
  Population-adjusted requirement (S9): `a E + m W^0.75 + x sqrt(a² σE² + (m dW^0.75/dW σW)²)`,
  with the BW term linearised (delta method) for the W^0.75 scaling.
  """
  def population_requirement(coefs, e, w, x, sigma_e, bw_cv) do
    w75 = :math.pow(w, 0.75)
    sd_w = w * bw_cv
    dw75 = 0.75 * :math.pow(w, -0.25)

    Map.new(coefs, fn {aa, %{a: a, m: m}} ->
      sd = :math.sqrt(a * a * sigma_e * sigma_e + :math.pow(m * dw75 * sd_w, 2))
      {aa, a * e + m * w75 + x * sd}
    end)
  end
end
