defprotocol CoffeeTimeFirmware.Hardware do
  def read_gpio(interface, gpio)
  def write_gpio(interface, key, value)

  def open_fill_level(interface)

  def read_boiler_probe_temp(interface)
  def read_internal_temperature(interface)
end
