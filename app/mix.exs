defmodule CoffeeTime.MixProject do
  use Mix.Project

  def project do
    [
      app: :coffee_time,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {CoffeeTime.Application, []},
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
      {:phoenix, "~> 1.7.7"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2",
       only: :dev, runtime: Mix.env() == :dev && Mix.target() == :host},
      {:phoenix_live_view, "~> 0.19.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:esbuild, "~> 0.5", runtime: Mix.env() == :dev && Mix.target() == :host},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev && Mix.target() == :host},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"}
    ] ++ nerves_deps()
  end

  defp nerves_deps() do
    [
      {:quantum, "~> 3.5"},
      {:compare_chain, ">= 0.0.0"},
      {:cubdb, "~> 2.0"},
      {:briefly, ">= 0.0.0", only: :test, optional: true},
      {:gen_state_machine, "~> 3.0"},
      # Dependencies for all targets
      {:circuits_gpio, "~> 1.0"},
      {:circuits_spi, "~> 1.3"},
      {:circuits_i2c, "~> 2.0", override: true},
      {:ads1115, "~> 0.2.1"},
      {:max31865, "~> 0.1.0", github: "benwilson512/max31865"},
      {:nerves_time_zones, "~> 0.3.0"}
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
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
