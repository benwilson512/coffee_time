defmodule CoffeeTimeFirmware.Hydraulics.FlowDebugger do
  @moduledoc """
  Applies a duty cycle to the boiler.

  There's some interesting nuance here when trying to rapidly switch an AC
  """

  use GenServer
  require Logger

  defstruct [:context, :gpio, counter: 0]

  def reset(context) do
    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.call(:reset)
  end

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(context.hardware, :flow)

    CoffeeTimeFirmware.Hardware.set_interrupts(context.hardware, gpio, :rising)

    state = %__MODULE__{
      context: context,
      gpio: gpio
    }

    {:ok, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, state.counter, %{state | counter: 0}}
  end

  def handle_info({:circuits_gpio, _, _, _}, state) do
    {:noreply, %{state | counter: state.counter + 1}}
  end
end
