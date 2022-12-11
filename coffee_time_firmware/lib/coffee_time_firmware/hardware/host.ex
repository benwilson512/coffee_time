defmodule CoffeeTimeFirmware.Hardware.Host do
  @pin_layout %{
    16 => {:pump, :output, initial_value: 1, pull_mode: :pullup},
    18 => {:boiler_fill_status, :input, initial_value: 0, pull_mode: :pulldown},
    20 => {:refill_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    21 => {:grouphead_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    22 => {:duty_cycle, :output, initial_value: 0},
    26 => {:flow_meter, :input, initial_value: 0, pull_mode: :pulldown}
  }
  defstruct pin_layout:
              Map.new(@pin_layout, fn
                {number, {name, io, opts}} ->
                  {name, {number, io, opts}}
              end)

  # This module hasn't really been kept up to date. The Mock impl is in good shape
  # to make test work, and the Pi one obviously is set up to make the Pi work, but I'm
  # not really running this on the host machine much these days

  defimpl CoffeeTimeFirmware.Hardware do
    def read_boiler_probe_temp(_) do
      100.0
    end

    def read_cpu_temperature(_) do
      35.0
    end

    def open_gpio(%{pin_layout: pin_layout}, key) do
      {number, io, opts} = Map.fetch!(pin_layout, key)
      Circuits.GPIO.open(number, io, opts)
    end

    def write_gpio(_, gpio, val) do
      Circuits.GPIO.write(gpio, val)
    end

    def read_gpio(_, gpio) do
      Circuits.GPIO.read(gpio)
    end

    def set_interrupts(_, gpio, trigger) do
      Circuits.GPIO.set_interrupts(gpio, trigger)
      Circuits.GPIO.pin(gpio)
    end
  end
end
