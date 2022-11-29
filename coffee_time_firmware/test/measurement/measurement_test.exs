defmodule CoffeeTimeFirmware.MeasurementTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  alias CoffeeTimeFirmware.Measurement

  setup %{context: context} do
    {:ok, _} =
      Measurement.start_link(%{
        context: context,
        intervals: %{
          Measurement.BoilerTempProbe => %{read_interval: :infinity},
          Measurement.BoilerFillStatus => %{
            idle_read_interval: :infinity,
            refill_read_interval: :infinity
          },
          Measurement.PiInternals => %{read_interval: :infinity}
        }
      })

    {:ok, %{context: context}}
  end

  test "boiler temp probe writes to the store correctly", %{context: context} do
    Measurement.Store.subscribe(context, :boiler_temp)
    boiler_pid = lookup_pid(context, Measurement.BoilerTempProbe)

    send(boiler_pid, :query)
    send(boiler_pid, {:boiler_temp, 25})

    assert_receive({:broadcast, :boiler_temp, 25})

    assert 25 == Measurement.Store.fetch!(context, :boiler_temp)
  end
end
