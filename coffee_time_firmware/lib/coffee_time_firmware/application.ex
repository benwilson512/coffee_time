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

    context = context()

    children =
      [
        {Registry, keys: :unique, name: context.registry, partitions: System.schedulers_online()},
        {Registry,
         keys: :duplicate, name: context.pubsub, partitions: System.schedulers_online()},
        {CoffeeTimeFirmware.Breakers,
         %{context: context, config: CoffeeTimeFirmware.Context.breaker_config()}},
        pi_only({Max31865.Server, [rtd_wires: 4, spi_device_cs_pin: 0]}),
        {CoffeeTimeFirmware.Measurement, %{context: context}}

        # {CoffeeTimeFirmware.Boiler, []}
      ]
      |> List.flatten()

    Supervisor.start_link(children, opts)
  end

  def context() do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub
    }
  end

  def name(context, atom) do
    {:via, Registry, {context.registry, atom}}
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
