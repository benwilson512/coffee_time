defmodule CoffeeTimeFirmware.Boiler.DutyCycle do
  use GenServer
  require Logger

  @moduledoc """
  Applies a duty cycle to the boiler.
  """

  defstruct [:context, :gpio, :write_interval, duty_cycle: 0, counter: 0]

  def set(context, int) when int in 0..10 do
    Logger.info("""
    Setting duty cycle: #{int}
    """)

    CoffeeTimeFirmware.PubSub.broadcast(context, :boiler_duty_cycle, int)

    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.cast({:set, int})
  end

  def block(context, val) do
    Logger.info("""
    Blocking DutyCycle: #{inspect(val)}
    """)

    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.call({:block, val})
  end

  def unblock(context, val) do
    Logger.info("""
    UnBlocking DutyCycle: #{inspect(val)}
    """)

    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.call({:unblock, val})
  end

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, intervals: %{__MODULE__ => %{write_interval: interval}}}) do
    {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_duty_cycle_pin(context.hardware)

    state = %__MODULE__{context: context, gpio: gpio, write_interval: interval}

    Process.send_after(self(), :tick, state.write_interval)

    {:ok, state}
  end

  def handle_call({:block, blocker}, _from, state) do
    state = Map.update!(state, :bockers, &MapSet.put(&1, blocker))
    {:reply, :ok, state, {:continue, :cycle}}
  end

  def handle_call({:unblock, blocker}, _from, state) do
    state = Map.update!(state, :bockers, &MapSet.delete(&1, blocker))
    {:reply, :ok, state, {:continue, :cycle}}
  end

  def handle_cast({:set, int}, state) do
    {:noreply, %{state | duty_cycle: int}, {:continue, :cycle}}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.write_interval)
    {:noreply, inc(state), {:continue, :cycle}}
  end

  def handle_continue(:cycle, state) do
    gpio_val =
      if state.counter < state.duty_cycle do
        1
      else
        0
      end

    CoffeeTimeFirmware.Hardware.write_gpio(state.context.hardware, state.gpio, gpio_val)
    {:noreply, state}
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
