defmodule CoffeeTimeFirmware.Boiler.FillLevel do
  use GenServer
  require Logger

  @moduledoc """
  Handles tracking the boiler fill level.
  """

  defstruct [:context, :gpio, :idle_read_interval, :refill_read_interval]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => intervals}}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_fill_level(context.hardware)

    state = %__MODULE__{
      context: context,
      gpio: gpio,
      idle_read_interval: intervals.idle_read_interval,
      refill_read_interval: intervals.refill_read_interval
    }

    Process.send_after(self(), :tick, state.idle_read_interval)

    {:ok, state}
  end

  def handle_info(:tick, state) do
    status = status_from_gpio(state.context, state.gpio)
    CoffeeTimeFirmware.PubSub.broadcast(state.context, :fill_level_status, status)
    {:noreply, state}
  end

  defp status_from_gpio(context, gpio) do
    case CoffeeTimeFirmware.Hardware.read_gpio(context.hardware, gpio) do
      1 ->
        :full

      0 ->
        :low
    end
  end
end
