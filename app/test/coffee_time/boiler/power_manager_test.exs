defmodule CoffeeTime.Boiler.PowerManagerTest do
  use CoffeeTime.ContextCase, async: true

  alias CoffeeTime.Boiler.PowerManager
  alias CoffeeTime.Boiler.PowerManager.Config
  alias CoffeeTime.Boiler
  alias CoffeeTime.Measurement

  @moduletag :measurement_store
  @moduletag :watchdog

  describe "initial boot process" do
    setup :boot

    @tag config: %Config{idle_pressure: 1000}
    test "if we boot without a sleep config we should be idle", %{
      context: context,
      config: config
    } do
      target = config.idle_pressure
      # should be idle
      assert {:idle, _} = get_state(context, PowerManager)
      # the power control should be set to our idle value
      assert {:hold_target, %{target: ^target}} =
               get_state(context, Boiler.PowerControl)
    end
  end

  describe "idle" do
    setup :boot

    @describetag config: %Config{
                   idle_pressure: 10300,
                   active_trigger_threshold: 9000,
                   active_pressure: 12000
                 }
    test "pressure below the active trigger moves us to active", %{
      context: context,
      config: config
    } do
      # should be idle
      assert {:idle, %{prev_pressure: 0}} = get_state(context, PowerManager)

      # send some pressure below our trigger
      Measurement.Store.put(context, :boiler_pressure, config.active_trigger_threshold - 1)

      # should be idle
      assert {:active, _} = get_state(context, PowerManager)
    end

    test "pressure drop less than 100 does nothing", %{context: context} do
      Measurement.Store.put(context, :boiler_pressure, 10300)

      # should be idle
      assert {:idle, %{prev_pressure: 10300}} = get_state(context, PowerManager)

      Measurement.Store.put(context, :boiler_pressure, 10250)

      # should still be idle
      assert {:idle, %{prev_pressure: 10250}} = get_state(context, PowerManager)
    end

    test "pressure drop more than 100 should put us in active", %{
      context: context,
      config: %{active_pressure: active_target}
    } do
      Measurement.Store.put(context, :boiler_pressure, 10300)

      # should be idle
      assert {:idle, %{prev_pressure: 10300}} = get_state(context, PowerManager)

      Measurement.Store.put(context, :boiler_pressure, 10150)

      assert {:active, %{prev_pressure: 10150}} =
               get_state(context, PowerManager)

      # the power control should be set to our active value
      assert {:hold_target, %{target: ^active_target}} =
               get_state(context, Boiler.PowerControl)
    end
  end

  describe "active" do
    setup [:boot, :activate]

    @describetag config: %Config{
                   idle_pressure: 10300,
                   active_trigger_threshold: 9000,
                   active_pressure: 12000,
                   active_duration: :infinity
                 }

    test "activate sets a timer once we get pressure above target", %{context: context} do
      assert {:active, %{active_timer: nil}} = get_state(context, PowerManager)
    end
  end

  def boot(%{context: context} = test_context) do
    config = test_context[:config] || %Config{}

    PowerManager.__set_config__(context, config)
    Measurement.Store.put(context, :boiler_fill_status, :full)

    params = %{
      context: context,
      intervals: %{
        Boiler.DutyCycle => %{write_interval: :infinity}
      }
    }

    start_supervised!({Boiler.DutyCycle, params})
    start_supervised!({Boiler.PowerControl, params})
    start_supervised!({PowerManager, params})

    :ok
  end

  def activate(%{context: context, config: config}) do
    Measurement.Store.put(context, :boiler_pressure, config.active_trigger_threshold - 1)
    :ok
  end
end
