defmodule CoffeeTime.Hardware.Host do
  require Logger

  @pin_layout %{
    6 => {:button1, :input, pull_mode: :pulldown},
    13 => {:button3, :input, pull_mode: :pulldown},
    19 => {:button2, :input, pull_mode: :pulldown},
    26 => {:button4, :input, pull_mode: :pulldown},
    {:stub, 1} => {:led1, :output, initial_value: 0},
    {:stub, 2} => {:led2, :output, initial_value: 0},
    {:stub, 3} => {:led3, :output, initial_value: 0},
    {:stub, 4} => {:led4, :output, initial_value: 0},
    17 => {:flow_meter, :input, pull_mode: :pulldown},
    16 => {:pump, :output, initial_value: 1, pull_mode: :pullup},
    18 => {:boiler_fill_probe, :input, initial_value: 0, pull_mode: :pulldown},
    20 => {:refill_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    21 => {:grouphead_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    22 => {:duty_cycle, :output, initial_value: 0}
  }
  defstruct pin_layout:
              Map.new(@pin_layout, fn
                {number, {name, io, opts}} ->
                  {name, {number, io, opts}}
              end)

  # This module hasn't really been kept up to date. The Mock impl is in good shape
  # to make test work, and the Pi one obviously is set up to make the Pi work, but I'm
  # not really running this on the host machine much these days

  defimpl CoffeeTime.Hardware do
    def read_boiler_probe_temp(_) do
      100.0
    end

    def open_i2c(_) do
      make_ref()
    end

    def read_boiler_pressure_sender(_, _) do
      9000
    end

    def read_cpu_temperature(_) do
      35.0
    end

    def read_one_wire_temperature(_, _) do
      37.0
    end

    def open_gpio(%{pin_layout: pin_layout}, key) do
      case Map.fetch!(pin_layout, key) do
        {{:stub, _} = stub, :output, _} ->
          {:ok, stub}

        {number, io, opts} ->
          Circuits.GPIO.open(number, io, opts)
      end
    end

    def set_interrupts(_, gpio, trigger) do
      Circuits.GPIO.set_interrupts(gpio, trigger)
      Circuits.GPIO.pin(gpio)
    end

    def write_gpio(_, {:stub, n}, val) do
      Logger.debug("write_gpio: #{n}, #{val}")
    end

    def write_gpio(_, gpio, val) do
      Circuits.GPIO.write(gpio, val)
    end

    def set_pull_mode(_interface, {:stub, n}, mode) do
      Logger.debug("changing pull mode: #{n}, #{mode}")
    end

    def set_pull_mode(_interface, gpio, mode) do
      Circuits.GPIO.set_pull_mode(gpio, mode)
    end

    def read_gpio(_, gpio) do
      Circuits.GPIO.read(gpio)
    end
  end
end
