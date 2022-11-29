defmodule CoffeeTimeFirmware.Hardware.Mock do
  defstruct [:pid]

  def set_gpio(pid, gpio, val, opts \\ []) do
    send(pid, {:gpio_val, gpio, val})

    unless opts[:async] do
      :sys.get_state(pid)
    end
  end

  defimpl CoffeeTimeFirmware.Hardware do
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

    def open_gpio(_, key) do
      {:ok, key}
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
