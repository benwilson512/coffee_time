defmodule CoffeeTimeFirmware.Boiler.ControlTest do
  use ExUnit.Case, async: true

  setup do
    registry = Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))
    pubsub = Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))

    context = %CoffeeTimeFirmware.Context{
      registry: registry,
      pubsub: pubsub,
      hardware: %CoffeeTimeFirmware.Hardware.Host{}
    }

    {:ok, x} = Registry.start_link(keys: :unique, name: context.registry, partitions: 1)
    {:ok, x} = Registry.start_link(keys: :duplicate, name: context.pubsub, partitions: 1)

    {:ok, %{context: context}}
  end

  test "foo", %{context: context} do
    {:ok, _} = CoffeeTimeFirmware.Boiler.start_link(%{context: context})
  end
end
