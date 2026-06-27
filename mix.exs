defmodule LeastCostFeed.MixProject do
  use Mix.Project

  def project do
    [
      app: :least_cost_feed,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {LeastCostFeed.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, ">= 0.0.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      heroicons_dep(),
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:nimble_csv, "~> 1.2"},
      {:timex, "~> 3.0"},
      {:number, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.6", only: :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": assets_setup_tasks(),
      "assets.build": ["tailwind least_cost_feed", "esbuild least_cost_feed"],
      "assets.deploy": [
        "tailwind least_cost_feed --minify",
        "esbuild least_cost_feed --minify",
        "phx.digest"
      ]
    ]
  end

  defp workspace_assets?, do: File.exists?(Path.expand("../shared_config/workspace_assets.ex", __DIR__))

  defp load_workspace_assets! do
    unless Code.ensure_loaded?(WorkspaceAssets) do
      Code.compile_file(Path.expand("../shared_config/workspace_assets.ex", __DIR__))
    end
  end

  defp heroicons_dep do
    if workspace_assets?() do
      load_workspace_assets!()
      WorkspaceAssets.heroicons_dep(__DIR__)
    else
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1}
    end
  end

  defp assets_setup_tasks do
    if workspace_assets?() do
      load_workspace_assets!()
      WorkspaceAssets.assets_setup_tasks(__DIR__)
    else
      ["tailwind.install --if-missing", "esbuild.install --if-missing"]
    end
  end
end
