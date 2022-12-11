defprotocol CoffeeTimeFirmware.Hardware do
  def read_gpio(interface, gpio)
  def write_gpio(interface, key, value)

  def open_gpio(interface, key)

  def set_interrupts(interface, gpio, trigger)

  def read_boiler_probe_temp(interface)
  def read_cpu_temperature(interface)
end
