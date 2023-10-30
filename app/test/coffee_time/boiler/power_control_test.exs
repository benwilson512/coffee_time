defmodule CoffeeTime.Boiler.PowerControlTest do
  use CoffeeTime.ContextCase, async: true

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.PubSub
  alias CoffeeTime.Boiler.PowerControl
  alias CoffeeTime.Boiler
  alias CoffeeTime.Measurement
  alias CoffeeTime.Watchdog

  @moduletag :measurement_store
  @moduletag :watchdog

  describe "initial boot process" do
    @tag :capture_log
    test "if there is a fault we are idle", %{context: context} do
      PubSub.subscribe(context, :watchdog)

      Watchdog.fault!(context, "test")

      assert_receive({:broadcast, :watchdog, :fault_state}, 200)

      assert :ignore == Boiler.start_link(%{context: context})
    end

    test "If there is no fault and a full boiler we move straigh to heating",
         %{
           context: context
         } = info do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      boot(info)

      assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))
    end

    test "If the boiler is low wait for it to be filled. Once it's full we heat",
         %{
           context: context
         } = info do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :low)

      boot(info)

      :ok = PowerControl.set_target(context, 127)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, PowerControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      Measurement.Store.put(context, :boiler_pressure, 124)
      assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))
      # Target temp is 128 but the current temp is 20, so we should be on
      # full power to get to temp.
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end

    test "If we don't yet know the status of the boiler we also wait for it to be filled",
         %{context: context} = info do
      boot(info)

      PowerControl.set_target(context, 128)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, PowerControl))
    end
  end

  describe "post boot boiler refill" do
    setup :boot

    test "low boiler status while heating turns off the heater", %{context: context} do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :full)
      :ok = PowerControl.set_target(context, 125)

      assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))
      Measurement.Store.put(context, :boiler_pressure, 120)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})

      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, PowerControl))
      # Turn the boiler power off while heating up as a safety precation.
      # this is probably overly conservative, but is an easy and safe default.
      # in the future we probably want to run it for a few seconds to help deal with the new hot water
      # and then shut off until we get the full signal.
      assert_receive({:broadcast, :boiler_duty_cycle, 0})

      # then when it's full we're back to heat
      Measurement.Store.put(context, :boiler_fill_status, :full)
      assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))
      # The duty cycle changes are only triggered when we get an update about the current temp
      Measurement.Store.put(context, :boiler_pressure, 120)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end
  end

  @tag :capture_log
  test "crashing resets to the correct state", %{context: context} do
    PubSub.subscribe(context, :boiler_duty_cycle)
    Measurement.Store.put(context, :boiler_fill_status, :full)

    params = %{
      context: context,
      intervals: %{
        Boiler.DutyCycle => %{write_interval: :infinity}
      }
    }

    start_supervised!({Boiler.DutyCycle, params})
    pid = start_supervised!({Boiler.PowerControl, params})

    # initial boot messages
    assert_receive({:broadcast, :boiler_duty_cycle, 0})
    assert_receive({:write_gpio, :duty_cycle, 0})

    :ok = PowerControl.set_target(context, 125)

    assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))

    # send a temp so we trigger heating
    Measurement.Store.put(context, :boiler_pressure, 120)
    assert_receive({:broadcast, :boiler_duty_cycle, 10})
    assert_receive({:write_gpio, :duty_cycle, 1})
    refute_receive(_)

    Process.monitor(pid)
    Process.exit(pid, :kill)

    assert_receive({:DOWN, _, :process, _, :killed})

    # it should reboot all the children, which means we get the boot messages again
    assert_receive({:broadcast, :boiler_duty_cycle, 0})
    assert_receive({:write_gpio, :duty_cycle, 0})

    # We're in the temp hold
    assert {:hold_target, _} = :sys.get_state(name(context, PowerControl))
  end

  def boot(%{context: context}) do
    params = %{
      context: context,
      intervals: %{
        Boiler.DutyCycle => %{write_interval: :infinity}
      }
    }

    start_supervised!({Boiler.DutyCycle, params})
    start_supervised!({Boiler.PowerControl, params})

    :ok
  end
end
