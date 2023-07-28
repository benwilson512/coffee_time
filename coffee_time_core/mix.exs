defmodule CoffeeTime.MixProject do
  use Mix.Project

  @app :coffee_time
  @version "0.1.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {CoffeeTime.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:quantum, "~> 3.5"},
      {:compare_chain, ">= 0.0.0"},
      {:cubdb, "~> 2.0"},
      {:jason, ">= 0.0.0"},
      {:briefly, ">= 0.0.0", only: :test},
      {:gen_state_machine, "~> 3.0"},
      # Dependencies for all targets
      {:circuits_gpio, "~> 1.0"},
      {:circuits_spi, "~> 1.3"},
      {:max31865, "~> 0.1.0", github: "benwilson512/max31865"},
      {:nerves_time_zones, "~> 0.3.0"}
    ]
  end
end
