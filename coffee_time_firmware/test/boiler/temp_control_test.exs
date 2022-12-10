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

      TempControl.set_target_temp(context, 128)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      Measurement.Store.put(context, :boiler_temp, 20)
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
