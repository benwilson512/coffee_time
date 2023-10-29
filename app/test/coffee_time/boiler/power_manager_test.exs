defmodule CoffeeTime.Boiler.PowerManagerTest do
  use CoffeeTime.ContextCase, async: true

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.PubSub
  alias CoffeeTime.Boiler.PowerControl
  alias CoffeeTime.Boiler.PowerManager
  alias CoffeeTime.Boiler.PowerManager.Config
  alias CoffeeTime.Boiler
  alias CoffeeTime.Measurement
  alias CoffeeTime.Watchdog

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
      assert {:idle, _} = :sys.get_state(name(context, Boiler.PowerManager))
      # the power control should be set to our idle value
      assert {:hold_target, %{target: ^target}} =
               :sys.get_state(name(context, Boiler.PowerControl))
    end
  end

  def boot(%{context: context} = test_context) do
    default_config = %{
      idle_pressure: 0
    }

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
    start_supervised!({Boiler.PowerManager, params})

    :ok
  end
end
