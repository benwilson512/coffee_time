defmodule CoffeeTime.Measurement.BoilerFillStatus do
  @moduledoc """
  Tracks the boiler fill level.
  """

  use GenServer
  require Logger

  alias CoffeeTime.Measurement
  alias CoffeeTime.Util

  defstruct [:context, :probe_gpio, :idle_read_interval, :refill_read_interval, status: :unknown]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => intervals}}) do
    {:ok, gpio} = CoffeeTime.Hardware.open_gpio(context.hardware, :boiler_fill_probe)

    state = %__MODULE__{
      context: context,
      probe_gpio: gpio,
      idle_read_interval: intervals.idle_read_interval,
      refill_read_interval: intervals.refill_read_interval
    }

    Util.send_after(self(), :tick, state.refill_read_interval)

    {:ok, state}
  end

  def handle_info(:tick, state) do
    status = status_from_gpio(state)

    Measurement.Store.put(state.context, :boiler_fill_status, status)

    state = %{state | status: status}

    Util.send_after(self(), :tick, interval_for_status(state))

    {:noreply, %{state | status: status}}
  end

  defp status_from_gpio(%__MODULE__{context: context, probe_gpio: gpio}) do
    # We switch to an internal pullup resistor. If the physical probe is still in contact
    # with the water then it will remain grounded, even though we are trying to pull it up.
    # If it is no longer in contact with the water then we will successfully pull it up to 1,
    # indicating that the water is low
    CoffeeTime.Hardware.set_pull_mode(context.hardware, gpio, :pullup)

    result =
      case CoffeeTime.Hardware.read_gpio(context.hardware, gpio) do
        0 ->
          :full

        1 ->
          :low
      end

    CoffeeTime.Hardware.set_pull_mode(context.hardware, gpio, :pulldown)

    result
  end

  defp interval_for_status(%{status: :full, idle_read_interval: interval}) do
    interval
  end

  defp interval_for_status(%{status: :low, refill_read_interval: interval}) do
    interval
  end
end
