# defmodule CoffeeTimeFirmware.Hardware.Pi do
#   @behaviour CoffeeTimeFirmware.Hardware.Interface

#   @boiler_fill_level_pin 18

#   def open_fill_level() do
#     Circuits.GPIO.open(@boiler_fill_level_pin, :input,
#       initial_value: 0,
#       pull_mode: :pulldown
#     )
#   end

#   def read_boiler_probe_temp(server) do
#     Max31865.get_temp(server)
#   end

#   def write_gpio(gpio, val) do
#     Circuits.GPIO.write(gpio, val)
#   end

#   def read_gpio(gpio) do
#     Circuits.GPIO.read(gpio)
#   end
# end
