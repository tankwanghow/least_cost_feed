defmodule LeastCostFeed.HenModel.Scenario do
  @moduledoc """
  Inputs for one simulation run (plain struct, no DB access).

  `programme` is a phase-feeding list `[%{from_week: 18, diet: %Diet{}}, ...]`.
  `nil` defaults are filled from parameters.csv by `resolve/1`.

  Configurable model choices (defaults are the pending-decision defaults of
  open_questions.md section C; each is documented in `priv/hen_model/README.md`):

    * `edition` - `:sea` (default) or `:global` guide
    * `energy_equation` - `:sakomura` (default), `:sakomura_alt`, `:emmans`
    * `energy_scaling` - `:guide_anchored` (default; k_m solved at
      `anchor_ref_temp`) or `:published` (k_m = `me_maint_scalar`)
    * `aa_maint_set` - `:a` (default) or `:b`
    * `heat_egg_weight` - `:intake` (default; heat acts only through intake)
      or `:explicit` (sourced S4 EW slopes applied to potential)
    * `energy_limit` - `:flock` (default) or `:per_hen` (see Population)
    * `overrides` - `%{param_id => number}` (e.g. `"intake_aa_drive_lambda"`)
  """

  alias LeastCostFeed.HenModel.Params

  defstruct programme: [],
            mode: :cycle,
            start_week: 18,
            end_week: 100,
            snapshot_week: 30,
            temp_c: nil,
            temp_max_c: nil,
            feather: nil,
            housing: :cage,
            hens_housed: 1000,
            edition: :sea,
            feed_price_per_kg: nil,
            egg_pricing: {:per_kg, nil},
            coarse_limestone_share: nil,
            energy_equation: :sakomura,
            energy_scaling: :guide_anchored,
            anchor_ref_temp: nil,
            aa_maint_set: :a,
            heat_egg_weight: :intake,
            energy_limit: :flock,
            n_hens: nil,
            overrides: %{}

  @doc "Fills nil defaults from parameters.csv and clamps the week range to the guide."
  def resolve(%__MODULE__{} = s) do
    ov = s.overrides
    temp = s.temp_c || Params.value("scenario_temp_mean_c", ov)

    egg_pricing =
      case s.egg_pricing do
        {:per_kg, nil} -> {:per_kg, Params.value_or_nil("egg_price_per_kg", ov)}
        other -> other
      end

    %{
      s
      | temp_c: temp * 1.0,
        temp_max_c: (s.temp_max_c || temp) * 1.0,
        feather: (s.feather || Params.value("scenario_feather_score", ov)) * 1.0,
        anchor_ref_temp: (s.anchor_ref_temp || Params.value("guide_anchor_ref_temp", ov)) * 1.0,
        n_hens: s.n_hens || round(Params.value("pop_n_hens", ov)),
        start_week: max(s.start_week, 18),
        end_week: min(s.end_week, 100),
        egg_pricing: egg_pricing
    }
  end
end
