defmodule CoffeeTimeFirmware.Hardware.Host do
  defstruct boiler_fill_level_pin: 18, duty_cycle_pin: 16

  defimpl CoffeeTimeFirmware.Hardware do
    def open_fill_level(host) do
      Circuits.GPIO.open(host.boiler_fill_level_pin, :input,
        initial_value: 0,
        pull_mode: :pulldown
      )
    end

    def open_duty_cycle_pin(host) do
      Circuits.GPIO.open(host.duty_cycle_pin, :output)
    end

    def read_boiler_probe_temp(_) do
      100.0
    end

    def read_cpu_temperature(_) do
      35.0
    end

    def write_gpio(_, gpio, val) do
      Circuits.GPIO.write(gpio, val)
    end

    def read_gpio(_, gpio) do
      Circuits.GPIO.read(gpio)
    end
  end
end
