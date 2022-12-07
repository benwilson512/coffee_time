defmodule CoffeeTimeFirmware.HydraulicsTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Hydraulics
  # alias CoffeeTimeFirmware.Hardware

  @moduletag :measurement_store

  setup %{context: context} do
    {:ok, _} =
      Hydraulics.start_link(%{
        context: context
      })

    {:ok, %{context: context}}
  end

  test "initial state is sane", %{context: context} do
    assert {:idle, _} = :sys.get_state(name(context, Hydraulics))
  end

  describe "boot process" do
    test "if the boiler is full we go to the ready state", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      Hydraulics.boot(context)

      assert {:ready, _} = :sys.get_state(name(context, Hydraulics))
    end

    test "If the boiler is low we refill it. Upon refill we go back to ready", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      Hydraulics.boot(context)

      assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))

      # 0s activate the relay not 1s here
      assert_receive({:write_gpio, :refill_solenoid, 0})
      assert_receive({:write_gpio, :pump, 0})

      Measurement.Store.put(context, :boiler_fill_status, :full)

      assert {:ready, _} = :sys.get_state(name(context, Hydraulics))

      assert_receive({:write_gpio, :refill_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end
  end

  describe "solenoid control" do
    setup :boot

    test "attempting to open a solenoid during a refill is refused", %{context: context} do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))
      assert Hydraulics.open_solenoid(context, :grouphead) == {:error, :busy}
    end

    test "attempting to turn on the pump during a refill is refused", %{context: context} do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))
      assert Hydraulics.activate_pump(context) == {:error, :busy}
    end

    test "we can open the grouphead solenoid", %{context: context} do
      assert :ok = Hydraulics.open_solenoid(context, :grouphead)

      # remember that solenoid control is ACTIVE LOW logic.
      assert_receive({:write_gpio, :grouphead_solenoid, 0})

      assert {{:holding_solenoid, _}, _} = :sys.get_state(name(context, Hydraulics))

      assert_receive({:write_gpio, :grouphead_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end

    test "we can turn on the pump while a solenoid is open", %{context: context} do
      assert :ok = Hydraulics.open_solenoid(context, :grouphead)
      assert :ok = Hydraulics.activate_pump(context)
    end

    test "we cannot turn on the pump when no solenoid is open", %{context: context} do
      assert {:error, :no_open_solenoid} = Hydraulics.activate_pump(context)
    end

    test "calling drive group head while it's in progress does nothing", %{context: context} do
      assert :ok = Hydraulics.open_solenoid(context, :grouphead)
      assert {:error, :busy} = Hydraulics.open_solenoid(context, :grouphead)
    end

    test "open solenoid delays boiler refill", %{context: context} do
      Hydraulics.open_solenoid(context, :grouphead)
      Measurement.Store.put(context, :boiler_fill_status, :low)
      # we wait for the grouphead to cycle
      assert_receive({:write_gpio, :grouphead_solenoid, 0})
      Hydraulics.halt(context)
      assert_receive({:write_gpio, :grouphead_solenoid, 1})

      assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))
      assert_receive({:write_gpio, :refill_solenoid, 0})
    end

    test "halt/1 can stop things", %{context: context} do
      Hydraulics.open_solenoid(context, :grouphead)
      assert_receive({:write_gpio, :grouphead_solenoid, 0})
      Hydraulics.halt(context)
      assert_receive({:write_gpio, :grouphead_solenoid, 1})
    end
  end

  defp boot(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    Hydraulics.boot(context)
    assert {:ready, _} = :sys.get_state(name(context, Hydraulics))
    info
  end
end
