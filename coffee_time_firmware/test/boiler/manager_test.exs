defmodule CoffeeTimeFirmware.Boiler.ManagerTest do
  use ExUnit.Case, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Boiler

  setup do
    context = %CoffeeTimeFirmware.Context{
      registry: unique_name(),
      pubsub: unique_name(),
      hardware: %CoffeeTimeFirmware.Hardware.Mock{
        pid: self()
      }
    }

    {:ok, _x} = Registry.start_link(keys: :unique, name: context.registry, partitions: 1)
    {:ok, _x} = Registry.start_link(keys: :duplicate, name: context.pubsub, partitions: 1)

    {:ok, _} =
      CoffeeTimeFirmware.Boiler.start_link(%{
        context: context,
        intervals: %{
          Boiler.TempProbe => %{read_interval: 0},
          Boiler.FillLevel => %{idle_read_interval: 0, refill_read_interval: 0},
          # The point of the large value here is that we never really want the timer to go off,
          # we are always going to trigger it manually for these tests
          Boiler.DutyCycle => %{write_interval: :timer.hours(1)}
        }
      })

    {:ok, %{context: context}}
  end

  test "foo", %{context: context} do
    Process.sleep(1000)
    flush()
  end

  defp flush() do
    receive do
      x ->
        x |> IO.inspect(label: :received)
        flush()
    after
      0 -> :ok
    end
  end

  defp unique_name() do
    Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))
  end
end
