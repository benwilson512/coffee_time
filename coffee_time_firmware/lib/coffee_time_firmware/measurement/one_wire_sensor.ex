defmodule CoffeeTimeFirmware.Measurement.OneWireSensor do
  @moduledoc """
  Fetches temp data from a 1 wire protocol sensor
  """

  use GenServer

  alias CoffeeTimeFirmware.Util

  defstruct [:context, :name, :read_interval]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, name: name, read_interval: read_interval}) do
    state = %__MODULE__{context: context, name: name, read_interval: read_interval}
    set_timer(state)
    {:ok, state}
  end

  def handle_info(:query, state) do
    # We intentionally do this first so that we stick to an overall tick rate as close to our target
    # as possible.
    set_timer(state)

    temp =
      CoffeeTimeFirmware.Hardware.read_one_wire_temperature(state.context.hardware, state.name)

    CoffeeTimeFirmware.Measurement.Store.put(state.context, state.name, temp)

    {:noreply, state}
  end

  defp set_timer(state) do
    Util.send_after(self(), :query, state.read_interval)
  end
end
