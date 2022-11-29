defmodule CoffeeTimeFirmware.WaterFlowTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.WaterFlow
  alias CoffeeTimeFirmware.Hardware

  @moduletag :pending

  setup %{context: context} do
    {:ok, _} =
      WaterFlow.start_link(%{
        context: context
      })

    pids =
      Map.new(
        [
          WaterFlow
        ],
        fn module ->
          [{pid, _}] = Registry.lookup(context.registry, module)
          {module, pid}
        end
      )

    {:ok, %{context: context, pids: pids}}
  end

  test "initial state is sane", %{context: context} do
    assert {:idle, _} = :sys.get_state(name(context, WaterFlow))
  end

  describe "boot process" do
    test "if the boiler is full we go to idle", %{
      context: context,
      pids: %{WaterFlow => fill_status_pid}
    } do
      WaterFlow.boot(context)
      Hardware.Mock.set_fill_status(fill_status_pid, 1)
      assert {:idle, _} = :sys.get_state(name(context, WaterFlow))
    end

    test "If the boiler is low we refill it. Upon refill we go back to idle", %{
      context: context,
      pids: %{WaterFlow => fill_status_pid}
    } do
      WaterFlow.boot(context)

      Hardware.Mock.set_fill_status(fill_status_pid, 0)

      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, Manager))

      Hardware.Mock.set_fill_status(fill_status_pid, 1)
      assert {:hold_temp, _} = :sys.get_state(name(context, Manager))
    end
  end
end
