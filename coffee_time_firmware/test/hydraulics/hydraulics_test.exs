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

  describe "espresso brewing" do
    setup :boot

    test "attempting to pull espresso during a refill is refused", %{context: context} do
      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))
      assert Hydraulics.drive_grouphead(context, {:timer, 0}) == {:error, :busy}
    end

    test "we can pull some espresso", %{context: context} do
      assert :ok = Hydraulics.drive_grouphead(context, {:timer, 0})

      assert_receive({:write_gpio, :grouphead_solenoid, 0})
      assert_receive({:write_gpio, :pump, 0})

      assert {{:driving_grouphead, _}, _} = :sys.get_state(name(context, Hydraulics))

      assert_receive({:write_gpio, :grouphead_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end

    test "calling drive group head while it's in progress does nothing", %{context: context} do
      assert :ok = Hydraulics.drive_grouphead(context, {:timer, :infinity})
      assert {:error, :busy} = Hydraulics.drive_grouphead(context, {:timer, :infinity})
    end

    test "pulling espresso delays boiler refill", %{context: context} do
      Hydraulics.drive_grouphead(context, {:timer, :infinity})
      Measurement.Store.put(context, :boiler_fill_status, :low)
      # we wait for the grouphead to cycle
      assert_receive({:write_gpio, :grouphead_solenoid, 0})
      send(lookup_pid(context, Hydraulics), :halt_grouphead)
      assert_receive({:write_gpio, :grouphead_solenoid, 1})

      assert {:boiler_filling, _} = :sys.get_state(name(context, Hydraulics))
      assert_receive({:write_gpio, :refill_solenoid, 0})
    end

    test "halt/1 can stop things early", %{context: context} do
      Hydraulics.drive_grouphead(context, {:timer, :infinity})
      assert_receive({:write_gpio, :grouphead_solenoid, 0})
      assert_receive({:write_gpio, :pump, 0})
      Hydraulics.halt(context)
      assert_receive({:write_gpio, :grouphead_solenoid, 1})
      assert_receive({:write_gpio, :pump, 1})
    end
  end

  defp boot(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    Hydraulics.boot(context)
    assert {:ready, _} = :sys.get_state(name(context, Hydraulics))
    info
  end
end
