defmodule CoffeeTimeFirmware.Measurement.FlowMeter do
  @moduledoc """
  Measures flow via the flow meter
  """
  alias CoffeeTimeFirmware.PubSub

  use GenServer
  require Logger

  defstruct [:context, :gpio]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(context.hardware, :flow_meter)

    CoffeeTimeFirmware.Hardware.set_interrupts(context.hardware, gpio, :rising)

    state = %__MODULE__{
      context: context,
      gpio: gpio
    }

    {:ok, state}
  end

  def handle_info({:circuits_gpio, _, time, val}, state) do
    PubSub.broadcast(state.context, :flow_pulse, {val, time})
    {:noreply, state}
  end
end
