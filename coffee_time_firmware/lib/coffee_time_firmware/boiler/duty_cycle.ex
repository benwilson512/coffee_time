defmodule CoffeeTimeFirmware.Boiler.DutyCycle do
  @moduledoc """
  Applies a duty cycle to the boiler.

  There's some interesting nuance here when trying to rapidly switch an AC
  """

  use GenServer
  require Logger

  alias CoffeeTimeFirmware.Util

  defstruct [:context, :gpio, write_interval: 100, duty_cycle: 0, counter: 1, subdivisions: 10]

  def set(context, int) when int in 0..10 do
    Logger.info("""
    Setting duty cycle: #{int}
    """)

    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.cast({:set, int})

    CoffeeTimeFirmware.PubSub.broadcast(context, :boiler_duty_cycle, int)

    :ok
  end

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => %{write_interval: interval}}}) do
    Process.flag(:trap_exit, true)
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(context.hardware, :duty_cycle)

    state = %__MODULE__{
      context: context,
      gpio: gpio,
      write_interval: interval
    }

    Util.send_after(self(), :tick, state.write_interval)

    {:ok, state}
  end

  # This exists to handle clean exits, such as if the process or application is restarted manually in
  # remote console. If it exits in an unexpected manner, it's the job of the `breakers` to initiate
  # a restart, since that's the only safe way to guarantee that the gpio pin drops back to 0.
  # TODO: Actually monitor this from breakers.
  def terminate(reason, %{context: context, gpio: gpio}) do
    CoffeeTimeFirmware.Hardware.write_gpio(context.hardware, gpio, 0)
    {:stop, reason}
  end

  def handle_cast({:set, int}, state) do
    {:noreply, %{state | duty_cycle: int}, {:continue, :cycle}}
  end

  def handle_info(:tick, state) do
    Util.send_after(self(), :tick, state.write_interval)

    {:noreply, inc(state), {:continue, :cycle}}
  end

  def handle_info({:EXIT, _pid, _}, state) do
    {:noreply, state}
  end

  def handle_continue(:cycle, state) do
    gpio_val =
      if state.counter <= state.duty_cycle do
        1
      else
        0
      end

    CoffeeTimeFirmware.Hardware.write_gpio(state.context.hardware, state.gpio, gpio_val)
    {:noreply, state}
  end

  defp inc(%{subdivisions: subdivisions} = state) do
    Map.update!(state, :counter, fn counter ->
      if counter >= subdivisions do
        1
      else
        counter + 1
      end
    end)
  end

  # def duty_cycle(length, num_ones) do
  #   {_, list} =
  #     Enum.reduce(1..length, {2 * num_ones - length, []}, fn _, {d, list} ->
  #       {d, val} = if d > 0, do: {d - 2 * length, 1}, else: {d, 0}
  #       {d + 2 * num_ones, [val | list]}
  #     end)

  #   list
  # end
end
