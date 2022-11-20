defmodule CoffeeTimeFirmware.Boiler.DutyCycle do
  use GenServer

  @moduledoc """
  Applies a duty cycle to the boiler.
  """

  alias Circuits.GPIO

  @tick_interval 100

  defstruct duty_cycle: 0, counter: 0, timer: nil, gpio: nil

  def set(int) when int in 0..10 do
    Logger.info("""
    Setting duty cycle: #{int}
    """)

    GenServer.cast(__MODULE__, {:set, int})
  end

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def init(_) do
    Process.send_after(self(), :tick, @tick_interval)
    # TODO: set GPIO pin.
    {:ok, %__MODULE__{}}
  end

  def handle_cast({:set, int}, state) do
    {:reply, :ok, %{state | duty_cycle: int}}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_interval)

    gpio_val =
      if state.counter < state.duty_cycle do
        1
      else
        0
      end

    GPIO.write(state.gpio, gpio_val)
    {:noreply, inc(state)}
  end

  defp inc(state) do
    Map.update!(state, :counter, fn
      counter when counter >= 10 ->
        0

      counter ->
        counter + 1
    end)
  end
end
