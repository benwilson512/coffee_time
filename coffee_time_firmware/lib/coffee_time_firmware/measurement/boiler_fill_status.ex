defmodule CoffeeTimeFirmware.Measurement.BoilerFillStatus do
  use GenServer
  require Logger

  alias CoffeeTimeFirmware.Util

  @moduledoc """
  Handles tracking the boiler fill level.

  I'm not sure honestly whether this module belongs here or in the water flow area. It's a water
  level sensor, so probably over there.
  """

  defstruct [:context, :gpio, :idle_read_interval, :refill_read_interval, status: :unknown]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  @pubsub_key :boiler_fill_level_status

  def check(context) do
    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.call(:check)
  end

  def init(%{context: context, intervals: %{__MODULE__ => intervals}}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_fill_level(context.hardware)

    state = %__MODULE__{
      context: context,
      gpio: gpio,
      idle_read_interval: intervals.idle_read_interval,
      refill_read_interval: intervals.refill_read_interval
    }

    Util.send_after(self(), :tick, state.idle_read_interval)

    {:ok, state}
  end

  def handle_call(:check, _from, state) do
    state =
      case state.status do
        :unknown ->
          status = status_from_gpio(state)
          %{state | status: status}

        _ ->
          state
      end

    {:reply, state.status, state}
  end

  def handle_info(:tick, state) do
    status = status_from_gpio(state)

    if status != state.status do
      CoffeeTimeFirmware.PubSub.broadcast(state.context, @pubsub_key, status)
    end

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
