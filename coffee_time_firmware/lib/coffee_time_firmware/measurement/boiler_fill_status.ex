defmodule CoffeeTimeFirmware.Measurement.BoilerFillStatus do
  @moduledoc """
  Tracks the boiler fill level.
  """

  use GenServer
  require Logger

  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Util

  defstruct [:context, :gpio, :idle_read_interval, :refill_read_interval, status: :unknown]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => intervals}}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(context.hardware, :boiler_fill_status)

    state = %__MODULE__{
      context: context,
      gpio: gpio,
      idle_read_interval: intervals.idle_read_interval,
      refill_read_interval: intervals.refill_read_interval
    }

    Util.send_after(self(), :tick, state.idle_read_interval)

    {:ok, state}
  end

  def handle_info(:tick, state) do
    status = status_from_gpio(state)

    Measurement.Store.put(state.context, :boiler_fill_status, status)

    state = %{state | status: status}

    Util.send_after(self(), :tick, interval_for_status(state))

    {:noreply, %{state | status: status}}
  end

  defp status_from_gpio(%{context: context, gpio: gpio}) do
    case CoffeeTimeFirmware.Hardware.read_gpio(context.hardware, gpio) do
      1 ->
        :full

      0 ->
        :low
    end
  end

  defp interval_for_status(%{status: :full, idle_read_interval: interval}) do
    interval
  end

  defp interval_for_status(%{status: :low, refill_read_interval: interval}) do
    interval
  end
end
