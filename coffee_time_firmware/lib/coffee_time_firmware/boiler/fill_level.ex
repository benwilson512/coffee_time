defmodule CoffeeTimeFirmware.Boiler.FillLevel do
  use GenServer
  require Logger

  @moduledoc """
  Handles tracking the boiler fill level.
  """

  @idle_tick_interval 1000
  @refill_tick_interval 100

  defstruct [:context, :gpio, state: :full, mode: :manual]

  def set_manual(state) when state in [:full, :low] do
    Logger.info("""
    Setting manual boiler refill state: #{state}
    """)

    GenServer.call(__MODULE__, {:set_manual, state})
  end

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context: context) do
    {:ok, gpio} = context.hardware.open_fill_level()

    state = state_from_gpio(context, gpio)

    state = %__MODULE__{context: context, gpio: gpio, state: state}

    Process.send_after(self(), :tick, tick_interval(state))

    {:ok, state}
  end

  defp tick_interval(_state) do
    1000
  end

  defp state_from_gpio(context, gpio) do
    case context.hardware.read_gpio(gpio) do
      1 ->
        :full

      0 ->
        :low
    end
  end
end