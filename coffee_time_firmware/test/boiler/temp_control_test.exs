defmodule CoffeeTimeFirmware.Boiler.TempControlTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Boiler.TempControl
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Measurement

  @moduletag :measurement_store

  setup %{context: context} do
    {:ok, _} =
      CoffeeTimeFirmware.Boiler.start_link(%{
        context: context,
        intervals: %{
          Boiler.DutyCycle => %{write_interval: :infinity}
        }
      })

    {:ok, %{context: context}}
  end

  test "initial state is sane", %{context: context} do
    assert %{duty_cycle: 0} = :sys.get_state(name(context, Boiler.DutyCycle))
    assert {:idle, _} = :sys.get_state(name(context, Boiler.TempControl))
  end

  describe "initial boot process" do
    test "If the boiler is full we move straight to heating", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :full)
      TempControl.boot(context)

      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
    end

    test "If the boiler is low we refill it. Upon refill we are in boot warmup", %{
      context: context
    } do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :low)

      TempControl.boot(context)
      TempControl.set_target_temp(context, 128)
      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      Measurement.Store.put(context, :boiler_temp, 20)
      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
      # Target temp is 128 but the current temp is 20, so we should be on
      # full power to get to temp.
      assert_receive({:broadcast, :boiler_duty_cycle, 10})
    end
  end

  describe "post boot boiler refill" do
    test "low boiler status while heating turns off the heater", %{context: context} do
      PubSub.subscribe(context, :boiler_duty_cycle)

      Measurement.Store.put(context, :boiler_fill_status, :full)
      :ok = TempControl.boot(context)
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
    end
  end
end
