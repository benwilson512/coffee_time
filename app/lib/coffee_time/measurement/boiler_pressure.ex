defmodule CoffeeTime.Measurement.BoilerPressure do
  @moduledoc """
  Fetches the Pi CPU temp
  """

  use GenServer

  alias CoffeeTime.Util

  defstruct [:context, target_interval: 200, i2c_ref: nil]

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    {:ok, i2c_ref} = CoffeeTime.Hardware.open_i2c(context.hardware)
    state = %__MODULE__{context: context, i2c_ref: i2c_ref}

    set_timer(state)
    {:ok, state}
  end

  def handle_info(:tick, state) do
    # We intentionally do this first so that we stick to an overall tick rate as close to our target
    # as possible.
    set_timer(state)

    pressure =
      CoffeeTime.Hardware.read_analog_value(
        state.context.hardware,
        state.i2c_ref,
        :boiler_pressure
      )

    CoffeeTime.Measurement.Store.put(state.context, :boiler_pressure, pressure)

    {:noreply, state}
  end

  defp set_timer(state) do
    Util.send_after(self(), :tick, state.target_interval)
  end
end
