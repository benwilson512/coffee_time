defmodule CoffeeTimeFirmware.Hardware.Mock do
  defstruct [:pid]

  defimpl CoffeeTimeFirmware.Hardware do
    def open_fill_level(_) do
      {:ok, :fill_level_stub}
    end

    def open_duty_cycle_pin(_) do
      {:ok, :duty_cycle_stub}
    end

    def read_boiler_probe_temp(_) do
      100.0
    end

    def read_internal_temperature(_) do
      35.0
    end

    def write_gpio(mock, gpio, val) do
      send(mock.pid, {:write_gpio, gpio, val})
    end

    def read_gpio(_, gpio) do
      receive do
        {:gpio_val, ^gpio, val} ->
          val
      end
    end
  end
end
