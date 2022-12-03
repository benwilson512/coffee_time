defmodule CoffeeTimeFirmware.Boiler.TempControlTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

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

  describe "boot process" do
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
      Measurement.Store.put(context, :boiler_fill_status, :low)

      TempControl.boot(context)

      assert {:awaiting_boiler_fill, _} = :sys.get_state(name(context, TempControl))

      Measurement.Store.put(context, :boiler_fill_status, :full)
      assert {:hold_temp, _} = :sys.get_state(name(context, TempControl))
    end
  end
end
