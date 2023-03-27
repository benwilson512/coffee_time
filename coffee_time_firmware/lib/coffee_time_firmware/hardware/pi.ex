defmodule CoffeeTimeFirmware.Hardware.Pi do
  # I wanted this in one place so that I could easily see how all of the pins are configured.
  # The input vs output distinction as well as the options are deeply intertwined with the physical
  # layout of the circuits. Whether it's a pull up or pull down resistor doesn't really matter
  # for the logic of the genserver, but it's very important for the circuit.
  @pin_layout %{
    # front panel
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
    18 => {:boiler_fill_probe, :input, initial_value: 1, pull_mode: :pulldown},
    20 => {:refill_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    21 => {:grouphead_solenoid, :output, initial_value: 1, pull_mode: :pullup},
    22 => {:duty_cycle, :output, initial_value: 0}
  }
  defstruct pin_layout:
              Map.new(@pin_layout, fn
                {number, {name, io, opts}} ->
                  {name, {number, io, opts}}
              end)

  defimpl CoffeeTimeFirmware.Hardware do
    require Logger

    def read_boiler_probe_temp(_) do
      Max31865.get_temp()
    end

    # TODO: some sort of mapping to support multiple 1 wire sensors
    @one_wire_file "/sys/bus/w1/devices/28-00044a381bff/temperature"
    def read_one_wire_temperature(_interface, _name) do
      @one_wire_file
      |> File.read!()
      |> String.trim()
      |> String.to_integer()
      |> Kernel./(1000)
    end

    @temperature_file "/sys/class/thermal/thermal_zone0/temp"
    def read_cpu_temperature(_) do
      @temperature_file
      |> File.read!()
      |> String.trim()
      |> String.to_integer()
      |> Kernel./(1000)
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

    def set_pull_mode(_, gpio, mode) do
      Circuits.GPIO.set_pull_mode(gpio, mode)
    end

    def read_gpio(_, gpio) do
      Circuits.GPIO.read(gpio)
    end
  end
end
