defmodule CoffeeTimeFirmware.ContextCase do
  use ExUnit.CaseTemplate

  setup info do
    context = %CoffeeTimeFirmware.Context{
      registry: unique_name(),
      pubsub: unique_name(),
      hardware: %CoffeeTimeFirmware.Hardware.Mock{
        pid: self()
      }
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
