defmodule CoffeeTime.MeasurementTest do
  use CoffeeTime.ContextCase, async: true

  alias CoffeeTime.Measurement
  alias CoffeeTime.Hardware

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
          Measurement.CpuTemp => %{read_interval: :infinity},
          Measurement.BoilerPressure => %{read_interval: :infinity}
        }
      })

    {:ok, %{context: context}}
  end

  describe "store can be written to by:" do
    test "boiler temp probe", %{context: context} do
      Measurement.Store.subscribe(context, :boiler_temp)
      boiler_pid = lookup_pid(context, Measurement.BoilerTempProbe)

      send(boiler_pid, :query)
      send(boiler_pid, {:boiler_temp, 25})

      assert_receive({:broadcast, :boiler_temp, 25})

      assert 25 == Measurement.Store.fetch!(context, :boiler_temp)
    end

    test "internal cpu temp", %{context: context} do
      Measurement.Store.subscribe(context, :cpu_temp)
      cpu_pid = lookup_pid(context, Measurement.CpuTemp)

      send(cpu_pid, :query)
      send(cpu_pid, {:cpu_temp, 30})

      assert_receive({:broadcast, :cpu_temp, 30})

      assert 30 == Measurement.Store.fetch!(context, :cpu_temp)
    end

    test "boiler fill status", %{context: context} do
      Measurement.Store.subscribe(context, :boiler_fill_status)
      fill_pid = lookup_pid(context, Measurement.BoilerFillStatus)

      send(fill_pid, :tick)
      Hardware.Mock.set_gpio(fill_pid, :boiler_fill_probe, 0)

      assert_receive({:broadcast, :boiler_fill_status, :full})

      assert :full == Measurement.Store.fetch!(context, :boiler_fill_status)
    end

    test "boiler pressure", %{context: context} do
      Measurement.Store.subscribe(context, :boiler_pressure)
      pressure_pid = lookup_pid(context, Measurement.BoilerPressure)

      send(pressure_pid, :tick)
      Hardware.Mock.set_analog_value(pressure_pid, :boiler_pressure, 1.0)

      assert_receive({:broadcast, :boiler_pressure, 1.0})

      assert 1.0 == Measurement.Store.fetch!(context, :boiler_pressure)
    end
  end
end
