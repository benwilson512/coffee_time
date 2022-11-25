defmodule CoffeeTimeFirmware.Boiler.ManagerTest do
  use ExUnit.Case, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Boiler.Manager
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Hardware

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
          Boiler.TempProbe => %{read_interval: :infinity},
          Boiler.FillStatus => %{idle_read_interval: :infinity, refill_read_interval: :infinity},
          # The point of the infinite value here is that we never really want the timer to go off,
          # we are always going to trigger it manually for these tests
          Boiler.DutyCycle => %{write_interval: :infinity}
        }
      })

    pids =
      Map.new(
        [
          Boiler.TempProbe,
          Boiler.FillStatus,
          Boiler.DutyCycle
        ],
        fn module ->
          [{pid, _}] = Registry.lookup(context.registry, module)
          {module, pid}
        end
      )

    {:ok, %{context: context, pids: pids}}
  end

  test "initial state is sane", %{context: context} do
    assert %{duty_cycle: 0} = :sys.get_state(name(context, Boiler.DutyCycle))
    assert {:idle, _} = :sys.get_state(name(context, Boiler.Manager))
  end

  describe "boot process" do
    test "If the boiler is full we move straight to heating", %{
      context: context,
      pids: %{Boiler.FillStatus => fill_status_pid}
    } do
      Manager.boot(context)

      Hardware.Mock.set_fill_status(fill_status_pid, 1)

      assert {:boot_warmup, _} = :sys.get_state(name(context, Manager))
    end

    test "If the boiler is low we refill it. Upon refill we are in boot warmup", %{
      context: context,
      pids: %{Boiler.FillStatus => fill_status_pid}
    } do
      Manager.boot(context)

      Hardware.Mock.set_fill_status(fill_status_pid, 0)

      assert {:boot_fill, _} = :sys.get_state(name(context, Manager))

      Hardware.Mock.set_fill_status(fill_status_pid, 1)
      assert {:boot_warmup, _} = :sys.get_state(name(context, Manager))
    end
  end

  defp unique_name() do
    Module.concat(__MODULE__, to_string(:erlang.unique_integer([:positive])))
  end
end
