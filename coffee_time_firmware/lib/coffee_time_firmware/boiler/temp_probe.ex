defmodule CoffeeTimeFirmware.Boiler.TempProbe do
  @moduledoc """
  Fetches the Boiler temperature
  """

  use GenServer

  defstruct [:context, target_interval: 200]

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    state = %__MODULE__{context: context}
    set_timer(state)
    {:ok, state}
  end

  def handle_info(:query, state) do
    # We intentionally do this first so that we stick to an overall tick rate as close to our target
    # as possible.
    set_timer(state)

    temp = CoffeeTimeFirmware.Hardware.read_boiler_probe_temp(state.context.hardware)

    # probably wrap in a try?
    CoffeeTimeFirmware.PubSub.broadcast(state.context, :boiler_temp, temp)

    {:noreply, state}
  end

  defp set_timer(state) do
    if state.target_interval < 75 do
      raise "Target interval should never be less than 75ms because it takes that long to read the sensor"
    else
      Process.send_after(self(), :query, state.target_interval)
    end
  end
end
