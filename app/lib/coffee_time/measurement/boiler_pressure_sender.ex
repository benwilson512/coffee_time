defmodule CoffeeTime.Measurement.BoilerPressureSender do
  @moduledoc """
  Fetches the Boiler temperature
  """

  use GenServer

  defstruct [:context, :read_interval, :i2c_ref]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => %{read_interval: read_interval}}}) do
    i2c_ref = CoffeeTime.Hardware.open_i2c(context.hardware)
    state = %__MODULE__{context: context, read_interval: read_interval, i2c_ref: i2c_ref}
    set_timer(state)
    {:ok, state}
  end

  def handle_info(:query, state) do
    # We intentionally do this first so that we stick to an overall tick rate as close to our target
    # as possible.
    set_timer(state)

    pressure =
      CoffeeTime.Hardware.read_boiler_pressure_sender(state.context.hardware, state.i2c_ref)

    # probably wrap in a try?
    CoffeeTime.Measurement.Store.put(state.context, :boiler_pressure, pressure)

    {:noreply, state}
  end

  defp set_timer(state) do
    CoffeeTime.Util.send_after(self(), :query, state.read_interval)
  end
end
