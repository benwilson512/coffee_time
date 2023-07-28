defmodule CoffeeTime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :rest_for_one, name: CoffeeTime.Supervisor]

    context = CoffeeTime.Context.new(target())

    children = children(context, Application.get_env(:coffee_time, :run))

    Supervisor.start_link(children, opts)
  end

  def children(context, true) do
    cubdb_opts = [
      name: CoffeeTime.Application.name(context, :db),
      data_dir: Path.join(context.data_dir, "coffeetime_db")
    ]

    panel_config = %{
      fault_blink_rate: 1000
    }

    [
      {Registry, keys: :unique, name: context.registry, partitions: System.schedulers_online()},
      {Registry, keys: :duplicate, name: context.pubsub, partitions: System.schedulers_online()},
      {CubDB, cubdb_opts},
      CoffeeTime.Scheduler,
      {CoffeeTime.Watchdog,
       %{context: context, config: CoffeeTime.Context.watchdog_config(target())}},
      # The control panel goes pretty high in the list because we want it to be able to reliably
      # display whatever is going on with the items below.
      {CoffeeTime.ControlPanel, %{context: context, config: panel_config}},
      # {CoffeeTime.ControlPanelDebugger, %{context: context}},
      {CoffeeTime.Measurement, %{context: context}},
      {CoffeeTime.Hydraulics, %{context: context}},
      {CoffeeTime.Boiler, %{context: context}},
      {CoffeeTime.Barista, %{context: context}}
    ]
    |> List.flatten()
  end

  def children(_, _) do
    []
  end

  def name(context, atom) do
    if context.root do
      atom
    else
      {:via, Registry, {context.registry, atom}}
    end
  end

  def db(context) do
    GenServer.whereis(CoffeeTime.Application.name(context, :db))
  end

  def pi_only(child) do
    case target() do
      :host -> []
      _ -> child
    end
  end

  def target() do
    Application.get_env(:coffee_time, :target)
  end
end
