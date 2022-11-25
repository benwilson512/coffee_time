defmodule CoffeeTimeFirmware.Hardware.Interface do
  @callback read_gpio(reference()) :: term()
  @callback write_gpio(reference(), term()) :: :ok

  @callback open_fill_level() :: {:ok, term()}

  @callback read_boiler_probe_temp(atom()) :: integer()
end
