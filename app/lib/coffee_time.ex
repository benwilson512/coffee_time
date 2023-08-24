defmodule CoffeeTime do
  @moduledoc """
  Convenience functions for easy CLI usage.
  """

  def get_fault() do
    CoffeeTime.Watchdog.get_fault(context())
  end

  def get_target_temp() do
    {_, %{target_temperature: target}} =
      context()
      |> CoffeeTime.Application.name(CoffeeTime.Boiler.PowerControl)
      |> :sys.get_state()

    target
  end

  def set_target(temp) do
    CoffeeTime.Boiler.PowerControl.set_target(context(), temp)
  end

  def status() do
    CoffeeTime.Measurement.Store.dump(context())
  end

  def run(program) do
    CoffeeTime.Barista.run_program(context(), program)
  end

  def halt() do
    CoffeeTime.Barista.halt(context())
  end

  defp context() do
    CoffeeTime.Context.new(:rpi3)
  end
end
