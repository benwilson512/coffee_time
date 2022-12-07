defmodule CoffeeTimeFirmware.ContextCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__), only: [lookup_pid: 2]
      import CoffeeTimeFirmware.Application, only: [name: 2]
    end
  end

  def lookup_pid(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    pid
  end

  setup info do
    dir = Briefly.create!(directory: true)

    context = %CoffeeTimeFirmware.Context{
      registry: unique_name(),
      pubsub: unique_name(),
      hardware: %CoffeeTimeFirmware.Hardware.Mock{
        pid: self()
      },
      data_dir: dir
    }

    {:ok, _x} = Registry.start_link(keys: :unique, name: context.registry, partitions: 1)
    {:ok, _x} = Registry.start_link(keys: :duplicate, name: context.pubsub, partitions: 1)

    if Map.get(info, :measurement_store) do
      {:ok, _} = CoffeeTimeFirmware.Measurement.Store.start_link(%{context: context})
    end

    {:ok, %{context: context}}
  end

  defp unique_name() do
    Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))
  end
end
