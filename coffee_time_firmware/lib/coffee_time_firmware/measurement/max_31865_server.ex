defmodule CoffeeTimeFirmware.Measurement.Max31865Server do
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(arg) do
    if CoffeeTimeFirmware.Application.target() == :rpi3 do
      Max31865.Server.start_link(arg)
    else
      :ignore
    end
  end
end
