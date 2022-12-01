defmodule CoffeeTimeFirmware.Hardware.Pi do
  # I wanted this in one place so that I could easily see how all of the pins are configured.
  # The input vs output distinction as well as the options are deeply intertwined with the physical
  # layout of the circuits. Whether it's a pull up or pull down resistor doesn't really matter
  # for the logic of the genserver, but it's very important for the circuit.
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

  defimpl CoffeeTimeFirmware.Hardware do
    def read_boiler_probe_temp(_) do
      Max31865.get_temp()
    end

    # 1 wire file "/sys/bus/w1/devices/28-00044a381bff/temperature"
    @temperature_file "/sys/class/thermal/thermal_zone0/temp"
    def read_cpu_temperature(_) do
      @temperature_file
      |> File.read!()
      |> String.trim()
      |> String.to_integer()
      |> Kernel./(1000)
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
  end
end
