defmodule CoffeeTime.Measurement.Max31865Server do
  @moduledoc """
  The Max31865.Server is an analog to digital convert used by the boiler temp probe.
  """
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(arg) do
    if CoffeeTime.Application.target() == :rpi3 do
      Max31865.Server.start_link(arg)
    else
      :ignore
    end
  end
end
