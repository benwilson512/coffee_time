defmodule CoffeeTime.Boiler.HeatControlTest do
  use CoffeeTime.ContextCase, async: true

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.PubSub
  alias CoffeeTime.Boiler.HeatControl
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

      boot(%{context: context})

      assert {:idle, _} = :sys.get_state(name(context, HeatControl))
    end

    test "If there is no fault and a full boiler we move straigh to heating",
         %{
           context: context
         } = info do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      boot(info)

      assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))
    end

    test "If the boiler is low wait for it to be filled. Once it's full we heat",
         %{
           context: context
         } = info do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :low)

      boot(info)

      :ok = HeatControl.set_target(context, 127)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, HeatControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      Measurement.Store.put(context, :boiler_temp, 124)
      assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))
      # Target temp is 128 but the current temp is 20, so we should be on
      # full power to get to temp.
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end

    test "If we don't yet know the status of the boiler we also wait for it to be filled",
         %{context: context} = info do
      boot(info)

      HeatControl.set_target(context, 128)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, HeatControl))
    end
  end

  describe "reheat process" do
    setup :boot

    test "low boiler temperature compared to the target temp triggers an initialization phase", %{
      context: context
    } do
      # boilerplate
      PubSub.subscribe(context, :boiler_duty_cycle)
      Measurement.Store.put(context, :boiler_fill_status, :full)

      # Set a high target temp, but then read a room temperature temp.
      HeatControl.set_target(context, 121)
      Measurement.Store.put(context, :boiler_temp, 34)

      # This should kick us into the boiler temp reheat
      assert {:hold_target, %{hold_mode: :reheat}} = :sys.get_state(name(context, HeatControl))

      # After another reading confirming our temp in this state we should
      # start heating
      Measurement.Store.put(context, :boiler_temp, 34)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})

      # Once we are more than the offset, we should turn off the boiler and start
      # the timer
      Measurement.Store.put(context, :boiler_temp, 116)
      assert_receive({:broadcast, :boiler_duty_cycle, 0})
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_timer
      assert state.hold_mode == :reheat

      # If we drop below the reduced temp we still add heat, but the timer should not change
      Measurement.Store.put(context, :boiler_temp, 115)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_timer
      assert state.hold_mode == :reheat

      # increment the offset all the way. This should kick us into maintain mode
      send(lookup_pid(context, HeatControl), {:reheat_increment, 5})
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      refute state.reheat_timer
      assert state.hold_mode == :maintain
    end

    test "reheat auto adjusts up", %{context: context} do
      # boilerplate
      PubSub.subscribe(context, :boiler_duty_cycle)
      Measurement.Store.put(context, :boiler_fill_status, :full)

      # Set a high target temp, but then read a room temperature temp.
      HeatControl.set_target(context, 121)
      Measurement.Store.put(context, :boiler_temp, 34)

      assert {:hold_target, %{hold_mode: :reheat} = state} =
               :sys.get_state(name(context, HeatControl))

      assert state.reheat_offset == -5

      # Once we are more than the offset, we should turn off the boiler and start
      # the timer
      Measurement.Store.put(context, :boiler_temp, 116)
      assert_receive({:broadcast, :boiler_duty_cycle, 0})
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_timer
      assert state.hold_mode == :reheat
      # the offset should still be -5 until the timer goes off
      assert state.reheat_offset == -5

      send(lookup_pid(context, HeatControl), {:reheat_increment, 0.5})

      # The offset should have been moved up, and the timer canceled.
      # It won't kick on again until we go above the offset threshold
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_offset == -4.5
      refute state.reheat_timer

      # We read a value that is still less than the offset threshold, so all the stuff should be
      # the same as before.
      Measurement.Store.put(context, :boiler_temp, 116.2)
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_offset == -4.5
      refute state.reheat_timer

      # We read above the offset threshold, so we kick off the timer to adjust it upward
      Measurement.Store.put(context, :boiler_temp, 116.5)
      assert {:hold_target, state} = :sys.get_state(name(context, HeatControl))
      assert state.reheat_offset == -4.5
      assert state.reheat_timer
    end

    test "reheat plays well with boiler fill", %{
      context: context
    } do
      # boilerplate
      PubSub.subscribe(context, :boiler_duty_cycle)
      Measurement.Store.put(context, :boiler_fill_status, :full)

      # Set a high target temp, but then read a room temperature temp.
      HeatControl.set_target(context, 121)
      Measurement.Store.put(context, :boiler_temp, 34)

      # This should kick us into the boiler temp reheat
      assert {:hold_target, %{hold_mode: :reheat}} = :sys.get_state(name(context, HeatControl))

      # We've heated up nicely and the timer is kicked off to go to maintainance mode
      Measurement.Store.put(context, :boiler_temp, 118)

      assert {:hold_target, %{reheat_timer: timer}} =
               :sys.get_state(name(context, HeatControl))

      assert timer

      # But now the boiler is low and we need water.
      Measurement.Store.put(context, :boiler_fill_status, :low)

      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, HeatControl))

      # The timer goes off while we are filling the boiler
      send(lookup_pid(context, HeatControl), {:reheat_increment, 5})

      Measurement.Store.put(context, :boiler_temp, 122)

      flush()

      # The hold mode should be adjusted
      assert {:awaiting_boiler_fill,
              %{hold_mode: :maintain, reheat_offset: -5, reheat_timer: nil}} =
               :sys.get_state(name(context, HeatControl))
    end
  end

  describe "post boot boiler refill" do
    setup :boot

    test "low boiler status while heating turns off the heater", %{context: context} do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :full)
      :ok = HeatControl.set_target(context, 125)

      assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))
      Measurement.Store.put(context, :boiler_temp, 120)
      assert_receive({:broadcast, :boiler_duty_cycle, 10})

      Measurement.Store.put(context, :boiler_fill_status, :low)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, HeatControl))
      # Turn the boiler power off while heating up as a safety precation.
      # this is probably overly conservative, but is an easy and safe default.
      # in the future we probably want to run it for a few seconds to help deal with the new hot water
      # and then shut off until we get the full signal.
      assert_receive({:broadcast, :boiler_duty_cycle, 0})

      # then when it's full we're back to heat
      Measurement.Store.put(context, :boiler_fill_status, :full)
      assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))
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
        {CoffeeTime.Boiler,
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

    :ok = HeatControl.set_target(context, 125)

    assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))

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
    assert {:hold_target, _} = :sys.get_state(name(context, HeatControl))
  end

  def boot(%{context: context}) do
    {:ok, _} =
      CoffeeTime.Boiler.start_link(%{
        context: context,
        intervals: %{
          Boiler.DutyCycle => %{write_interval: :infinity}
        }
      })

    :ok
  end
end
