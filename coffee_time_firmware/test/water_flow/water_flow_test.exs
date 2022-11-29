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

  describe "espresso brewing" do
    setup :boot

    test "attempting to pull espresso during a refill is refused", %{context: context} do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert assert {:boiler_filling, _} = :sys.get_state(name(context, WaterFlow))
      assert WaterFlow.drive_grouphead(context, {:timer, 0}) == {:error, :busy}
    end

    test "we can pull some espresso", %{context: context} do
      WaterFlow.drive_grouphead(context, {:timer, 0})

      assert_receive({:write_gpio, :refill_solenoid, 0})
      assert_receive({:write_gpio, :pump, 0})

      assert {:driving_grouphead, _} = :sys.get_state(name(context, WaterFlow))

      assert_receive({:write_gpio, :refill_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end

    test "pulling espresso delays boiler refill", %{context: context} do
      WaterFlow.drive_grouphead(context, {:timer, :infinity})
      Measurement.Store.put(context, :boiler_fill_status, :low)
      # we wait for the grouphead to cycle
      assert_receive({:write_gpio, :refill_solenoid, 0})
      send(lookup_pid(context, WaterFlow), :halt_grouphead)
      assert_receive({:write_gpio, :refill_solenoid, 1})

      assert {:boiler_filling, _} = :sys.get_state(name(context, WaterFlow))
    end
  end

  defp boot(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    WaterFlow.boot(context)
    assert {:ready, _} = :sys.get_state(name(context, WaterFlow))
    info
  end
end
