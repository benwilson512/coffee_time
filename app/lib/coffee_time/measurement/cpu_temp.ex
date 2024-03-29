defmodule CoffeeTime.Measurement.CpuTemp do
  @moduledoc """
  Fetches the Pi CPU temp
  """

  use GenServer

  alias CoffeeTime.Util

  defstruct [:context, target_interval: 5000]

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
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

    temp = CoffeeTime.Hardware.read_cpu_temperature(state.context.hardware)

    CoffeeTime.Measurement.Store.put(state.context, :cpu_temp, temp)

    {:noreply, state}
  end

  defp set_timer(state) do
    Util.send_after(self(), :query, state.target_interval)
  end
end
