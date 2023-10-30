defprotocol CoffeeTime.Hardware do
  def read_gpio(interface, gpio)
  def write_gpio(interface, key, value)

  def open_gpio(interface, key)

  def open_i2c(interface)

  def set_pull_mode(interface, gpio, mode)

  def set_interrupts(interface, gpio, trigger)

  def read_boiler_probe_temp(interface)

  def read_boiler_pressure_sender(interface, ref)

  def read_cpu_temperature(interface)

  def read_one_wire_temperature(interface, name)
end
