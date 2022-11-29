defmodule CoffeeTimeFirmware.WaterFlowTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.WaterFlow
  # alias CoffeeTimeFirmware.Hardware

  @moduletag :measurement_store

  setup %{context: context} do
    {:ok, _} =
      WaterFlow.start_link(%{
        context: context
      })

    {:ok, %{context: context}}
  end

  test "initial state is sane", %{context: context} do
    assert {:idle, _} = :sys.get_state(name(context, WaterFlow))
  end

  describe "boot process" do
    test "if the boiler is full we go to the ready state", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      WaterFlow.boot(context)

      assert {:ready, _} = :sys.get_state(name(context, WaterFlow))
    end

    test "If the boiler is low we refill it. Upon refill we go back to ready", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      WaterFlow.boot(context)

      assert {:boiler_filling, _} = :sys.get_state(name(context, WaterFlow))

      # 0s activate the relay not 1s here
      assert_receive({:write_gpio, :refill_solenoid, 0})
      assert_receive({:write_gpio, :pump, 0})

      Measurement.Store.put(context, :boiler_fill_status, :full)

      assert {:ready, _} = :sys.get_state(name(context, WaterFlow))

      assert_receive({:write_gpio, :refill_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end
  end
end
