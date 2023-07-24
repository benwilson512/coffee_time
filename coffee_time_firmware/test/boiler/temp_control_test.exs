defmodule CoffeeTimeFirmware.Boiler.TempControlTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Boiler.TempControl
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Watchdog

  @moduletag :measurement_store
  @moduletag :watchdog

  describe "initial boot process" do
    @tag :capture_log
    test "if there is a fault we are idle", %{context: context} do
      PubSub.subscribe(context, :watchdog)

      Watchdog.fault!(context, "test")

      assert_receive({:broadcast, :watchdog, :fault_state}, 200)

      boot(%{context: context})

      assert {:idle, _} = :sys.get_state(name(context, TempControl))
    end

    test "If there is no fault and a full boiler we move straigh to heating",
         %{
           context: context
         } = info do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      boot(info)

      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
    end

    test "If the boiler is low wait for it to be filled. Once it's full we heat",
         %{
           context: context
         } = info do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :low)

      boot(info)

      :ok = TempControl.set_target_temp(context, 127)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      Measurement.Store.put(context, :boiler_temp, 124)
      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
      # Target temp is 128 but the current temp is 20, so we should be on
      # full power to get to temp.
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end

    test "If we don't yet know the status of the boiler we also wait for it to be filled",
         %{context: context} = info do
      boot(info)

      TempControl.set_target_temp(context, 128)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))
    end
  end

  describe "init_boot phase" do
    setup :boot

    test "low boiler temperature compared to the target temp triggers an initialization phase", %{
      context: context
    } do
      # boilerplate
      PubSub.subscribe(context, :boiler_duty_cycle)
      Measurement.Store.put(context, :boiler_fill_status, :full)

      # Set a high target temp, but then read a room temperature temp.
      TempControl.set_target_temp(context, 121)
      Measurement.Store.put(context, :boiler_temp, 34)

      # This should kick us into the boiler temp backoff
      assert {:hold_temp, %{hold_mode: :backoff}} = :sys.get_state(name(context, TempControl))

      # After another reading confirming our temp in this state we should
      # start heating
      Measurement.Store.put(context, :boiler_temp, 34)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})

      # Once we are more than the offset, we should turn off the boiler and start
      # the timer
      Measurement.Store.put(context, :boiler_temp, 116)
      assert_receive({:broadcast, :boiler_duty_cycle, 0})
      assert {:hold_temp, state} = :sys.get_state(name(context, TempControl))
      assert state.temp_backoff_timer
      assert state.hold_mode == :backoff

      # If we drop below the reduced temp we still add heat, but the timer should not change
      Measurement.Store.put(context, :boiler_temp, 115)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
      assert {:hold_temp, state} = :sys.get_state(name(context, TempControl))
      assert state.temp_backoff_timer
      assert state.hold_mode == :backoff

      # Sending the booted message should kick us over to hold temp, and we shouldn't have the timer anymore.
      send(lookup_pid(context, TempControl), :gomax)
      assert {:hold_temp, state} = :sys.get_state(name(context, TempControl))
      refute state.temp_backoff_timer
      assert state.hold_mode == :max
    end
  end

  describe "post boot boiler refill" do
    setup :boot

    test "low boiler status while heating turns off the heater", %{context: context} do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :full)
      :ok = TempControl.set_target_temp(context, 125)

      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
      Measurement.Store.put(context, :boiler_temp, 120)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})

      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))
      # Turn the boiler power off while heating up as a safety precation.
      # this is probably overly conservative, but is an easy and safe default.
      # in the future we probably want to run it for a few seconds to help deal with the new hot water
      # and then shut off until we get the full signal.
      assert_receive({:broadcast, :boiler_duty_cycle, 0})

      # then when it's full we're back to heat
      Measurement.Store.put(context, :boiler_fill_status, :full)
      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
      # The duty cycle changes are only triggered when we get an update about the current temp
      Measurement.Store.put(context, :boiler_temp, 120)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end
  end

  @tag :capture_log
  test "crashing resets to the correct state", %{context: context} do
    PubSub.subscribe(context, :boiler_duty_cycle)
    Measurement.Store.put(context, :boiler_fill_status, :full)

    pid =
      start_supervised!(
        {CoffeeTimeFirmware.Boiler,
         %{
           context: context,
           intervals: %{
             Boiler.DutyCycle => %{write_interval: :infinity}
           }
         }}
      )

    # initial boot messages
    assert_receive({:broadcast, :boiler_duty_cycle, 0})
    assert_receive({:write_gpio, :duty_cycle, 0})

    :ok = TempControl.set_target_temp(context, 125)

    assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))

    # send a temp so we trigger heating
    Measurement.Store.put(context, :boiler_temp, 120)
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
    assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
  end

  def boot(%{context: context}) do
    {:ok, _} =
      CoffeeTimeFirmware.Boiler.start_link(%{
        context: context,
        intervals: %{
          Boiler.DutyCycle => %{write_interval: :infinity}
        }
      })

    :ok
  end
end
