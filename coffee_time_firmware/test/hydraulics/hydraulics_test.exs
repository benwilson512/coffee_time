defmodule CoffeeTimeFirmware.HydraulicsTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Watchdog
  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Hydraulics
  # alias CoffeeTimeFirmware.Hardware

  @moduletag :measurement_store
  @moduletag :watchdog

  describe "boot process" do
    @tag :capture_log
    test "If there is a fault we go to the idle state", %{
      context: context
    } do
      PubSub.subscribe(context, :watchdog)

      Watchdog.fault!(context, "test")

      assert_receive({:broadcast, :watchdog, :fault_state})

      {:ok, _} =
        Hydraulics.start_link(%{
          context: context
        })

      assert {:idle, _} = :sys.get_state(name(context, Hydraulics))
    end

    test "if there is no fault we are ready to go", %{context: context} do
      {:ok, _} =
        Hydraulics.start_link(%{
          context: context
        })

      assert {:ready, _} = :sys.get_state(name(context, Hydraulics))
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
    {:ok, _} =
      Hydraulics.start_link(%{
        context: context
      })

    assert {:ready, _} = :sys.get_state(name(context, Hydraulics))
    info
  end
end
