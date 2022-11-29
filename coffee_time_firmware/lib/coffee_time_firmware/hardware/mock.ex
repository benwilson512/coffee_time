defmodule CoffeeTimeFirmware.Hardware.Mock do
  defstruct [:pid]

  def set_fill_status(pid, val, opts \\ []) do
    send(pid, :tick)
    send(pid, {:gpio_val, :fill_level_stub, val})

    unless opts[:async] do
      :sys.get_state(pid)
    end
  end

  defimpl CoffeeTimeFirmware.Hardware do
    def open_fill_level(_) do
      {:ok, :fill_level_stub}
    end

    def open_duty_cycle_pin(_) do
      {:ok, :duty_cycle_stub}
    end

    def read_boiler_probe_temp(_) do
      receive do
        {:boiler_temp, val} ->
          val
      end
    end

    def read_cpu_temperature(_) do
      receive do
        {:cpu_temp, val} ->
          val
      end
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
