defmodule CoffeeTimeFirmware.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :rest_for_one, name: CoffeeTimeFirmware.Supervisor]

    context = CoffeeTimeFirmware.Context.new(target())

    children = children(context, Application.get_env(:coffee_time_firmware, :run))

    Supervisor.start_link(children, opts)
  end

  def children(context, true) do
    [
      {Registry, keys: :unique, name: context.registry, partitions: System.schedulers_online()},
      {Registry, keys: :duplicate, name: context.pubsub, partitions: System.schedulers_online()},
      {CoffeeTimeFirmware.Watchdog,
       %{context: context, config: CoffeeTimeFirmware.Context.watchdog_config(target())}},
      {CoffeeTimeFirmware.Measurement, %{context: context}},
      {CoffeeTimeFirmware.Boiler, %{context: context}},
      {CoffeeTimeFirmware.WaterFlow, %{context: context}}
    ]
    |> List.flatten()
  end

  def children(_, _) do
    []
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
