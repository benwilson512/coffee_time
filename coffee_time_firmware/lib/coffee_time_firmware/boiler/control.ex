defmodule CoffeeTimeFirmware.Boiler.Control do
  use GenServer

  @moduledoc """
  Determines whether the boiler heater element should be running.

  At the moment this is a simple thermostat. There is a minimum and a maximum threshold
  and this module keeps the temperature between those bounds. In the future this should be a PID loop.
  """

  defstruct context: nil

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    state = %__MODULE__{context: context}
    {:ok, state}
  end
end
