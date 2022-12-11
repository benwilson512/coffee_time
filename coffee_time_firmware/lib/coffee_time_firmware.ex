defmodule CoffeeTimeFirmware do
  @moduledoc """
  Convenience functions for easy CLI usage.
  """

  def get_fault() do
    CoffeeTimeFirmware.Watchdog.get_fault(context())
  end

  def get_target_temp() do
    {_, %{target_temperature: target}} =
      context()
      |> CoffeeTimeFirmware.Application.name(CoffeeTimeFirmware.Boiler.TempControl)
      |> :sys.get_state()

    target
  end

  def set_target_temp(temp) do
    CoffeeTimeFirmware.Boiler.TempControl.set_target_temp(context(), temp)
  end

  def status() do
    CoffeeTimeFirmware.Measurement.Store.dump(context())
  end

  def run(program) do
    CoffeeTimeFirmware.Barista.run_program(context(), program)
  end

  defp context() do
    CoffeeTimeFirmware.Context.new(:rpi3)
  end
end
