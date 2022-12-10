defmodule CoffeeTimeFirmware do
  @moduledoc """
  Documentation for CoffeeTimeFirmware.
  """

  def get_fault() do
    CoffeeTimeFirmware.Watchdog.get_fault(CoffeeTimeFirmware.Context.new(:rpi3))
  end
end
