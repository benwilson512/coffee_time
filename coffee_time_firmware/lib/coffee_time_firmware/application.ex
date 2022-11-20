defmodule CoffeeTimeFirmware.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CoffeeTimeFirmware.Supervisor]

    children =
      [
        pi_only({Max31865.Server, [rtd_wires: 4, spi_device_cs_pin: 0]}),
        {CoffeeTimeFirmware.Measurement, []},
        # {CoffeeTimeFirmware.Breakers, []},
        # {CoffeeTimeFirmware.Boiler, []}
      ]
      |> List.flatten()

    Supervisor.start_link(children, opts)
  end

  def pi_only(child) do
    case target() do
      :host -> []
      _ -> child
    end
  end

  def target() do
    Application.get_env(:coffee_time_firmware, :target)
  end
end
