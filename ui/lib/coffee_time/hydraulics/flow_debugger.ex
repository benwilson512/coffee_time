defmodule CoffeeTime.Hydraulics.FlowDebugger do
  @moduledoc """
  Helps debug the flow meter.
  """

  use GenServer
  require Logger

  defstruct [:context, :gpio, counters: %{}]

  def reset(context) do
    context
    |> CoffeeTime.Application.name(__MODULE__)
    |> GenServer.call(:reset)
  end

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context}) do
    {:ok, gpio} = CoffeeTime.Hardware.open_gpio(context.hardware, :flow)

    CoffeeTime.Hardware.set_interrupts(context.hardware, gpio, :rising)

    state = %__MODULE__{
      context: context,
      gpio: gpio
    }

    {:ok, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, state.counters, %{state | counters: %{}}}
  end

  def handle_info({:circuits_gpio, _, _, val}, state) do
    {:noreply, %{state | counters: Map.update(state.counters, val, 1, &(&1 + 1))}}
  end
end
