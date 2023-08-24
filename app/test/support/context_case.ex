defmodule CoffeeTime.ContextCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__), only: [lookup_pid: 2, flush: 0]
      import CoffeeTime.Application, only: [name: 2]
    end
  end

  def lookup_pid(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    pid
  end

  def flush() do
    receive do
      _msg ->
        flush()
    after
      0 ->
        :ok
    end
  end

  setup info do
    dir = Briefly.create!(directory: true)

    context = %CoffeeTime.Context{
      registry: unique_name(),
      pubsub: unique_name(),
      hardware: %CoffeeTime.Hardware.Mock{
        pid: self()
      },
      data_dir: dir
    }

    cubdb_opts = [
      name: CoffeeTime.Application.name(context, :db),
      data_dir: Path.join(context.data_dir, "coffeetime_db")
    ]

    {:ok, _x} = Registry.start_link(keys: :unique, name: context.registry, partitions: 1)
    {:ok, _x} = Registry.start_link(keys: :duplicate, name: context.pubsub, partitions: 1)
    {:ok, _x} = CubDB.start_link(cubdb_opts)

    if config = watchdog_config(info) do
      start_supervised!(
        {CoffeeTime.Watchdog,
         %{
           context: context,
           config: config
         }}
      )
    end

    if Map.get(info, :measurement_store) do
      {:ok, _} = CoffeeTime.Measurement.Store.start_link(%{context: context})
    end

    {:ok, %{context: context}}
  end

  defp watchdog_config(info) do
    default_config = %{
      reboot_on_fault: false,
      deadline: %{
        pump: :infinity,
        grouphead_solenoid: :infinity,
        refill_solenoid: :infinity
      },
      healthcheck: %{
        cpu_temp: :infinity,
        boiler_temp: :infinity,
        boiler_fill_status: :infinity
      },
      bound: %{
        cpu_temp: 0..1000,
        boiler_temp: 0..1000
      }
    }

    case info do
      %{watchdog: true} ->
        default_config

      %{watchdog: config_overrides} ->
        deep_merge(default_config, config_overrides)

      _ ->
        nil
    end
  end

  defp deep_merge(default, overrides) do
    Map.merge(default, overrides, fn
      _, %{} = val1, %{} = val2 ->
        deep_merge(val1, val2)

      _, _, val2 ->
        val2
    end)
  end

  defp unique_name() do
    Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))
  end
end
