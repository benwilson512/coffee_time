defmodule CoffeeTimeFirmware.Breakers do
  use GenServer

  require Logger

  @moduledoc """
  Identifies and logs faults, shutting down the pi if any are found.

  ## Fault Types

  ### Deadlines

  One major category of fault relates to not getting data when we expect. Each of the sub systems like
  the boiler or CPU temp is supposed to be checking things regularly and broadcasting a value. If we go
  several seconds without seeing one such value, it's a fault.

  Some deadline timers are intermittant. For example, when the boiler goes above 80% power, we expect that
  it should spend no more than 1 minute at or above that power level, unless we're in a boot condition. If we
  sit at that power level for more than 1 minute, it's a fault. When we return below that power level,
  no timer needs to be set.

  ### Aberant Values

  When we do get values, we do a sanity check those values to see if
  """

  defstruct [
    :context,
    :fault_deadlines,
    timers: %{},
    fault: nil,
    # TODO: Switch this to shutdown once we have real power hooked to this
    # fault_mode: :shutdown
    fault_mode: :inspect
  ]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def put_fault_deadline(context, key, value) do
    context
    |> CoffeeTimeFirmware.Application.name(__MODULE__)
    |> GenServer.call({:put_fault_deadline, key, value})
  end

  def init(%{context: context, config: config}) do
    state =
      %__MODULE__{
        context: context,
        fault_deadlines: config.fault_deadlines,
        fault_mode: fault_mode(config)
      }
      |> reset_timers(:all)

    CoffeeTimeFirmware.PubSub.subscribe(context, :boiler_temp)

    {:ok, state, {:continue, :maybe_shutdown}}
  end

  def handle_call({:put_fault_deadline, key, value}, _from, state) do
    state =
      state
      |> Map.update!(:fault_deadlines, fn fault_deadlines ->
        Map.replace!(fault_deadlines, key, value)
      end)
      |> reset_timers([key])

    {:reply, state.fault_deadlines, state}
  end

  def handle_info({:fault, fault_key, condition}, %{fault: nil} = state) do
    Logger.error("""
    ** FAULT DETECTED **
    Key: #{inspect(fault_key)}
    Condition: #{inspect(condition)}
    """)

    state = %{state | fault: fault_key}

    {:noreply, state, {:continue, :maybe_shutdown}}
  end

  def handle_info({:broadcast, :boiler_temp, val}, state) do
    if val > 130 do
      Logger.error("shutting down from too much temp")
      :init.stop()
    end

    {:noreply, reset_timers(state, [:boiler_temp_update])}
  end

  def handle_continue(:maybe_shutdown, %{fault_mode: fault_mode, fault: fault} = state)
      when fault != nil do
    case fault_mode do
      :inspect ->
        Logger.warn("Shutdown prevented, fault_mode: #{inspect(fault_mode)}")

      _ ->
        Logger.warn("""
        System shutting down, fault_mode: #{inspect(fault_mode)}
        """)

        # :init.stop(1)
    end

    {:noreply, state}
  end

  def handle_continue(:maybe_shutdown, state) do
    {:noreply, state}
  end

  # Resets one or more timers. Pass in the special `:all` key to reset all timers.
  # In essence, this goes through the `fault_deadlines` map and for each fault, sets a
  # timer according to its deadline.
  defp reset_timers(state, keys) do
    timers_to_update =
      case List.wrap(keys) do
        [:all] ->
          state.fault_deadlines

        keys ->
          Map.take(state.fault_deadlines, keys)
      end

    timers =
      Enum.reduce(timers_to_update, state.timers, fn {deadline_key, deadline_time}, timers ->
        timer = Process.send_after(self(), {:fault, deadline_key, deadline_time}, deadline_time)

        Map.update(timers, deadline_key, timer, fn existing_timer ->
          Process.cancel_timer(existing_timer)
          timer
        end)
      end)

    %{state | timers: timers}
  end

  defp fault_mode(_config) do
    # {:ok, gpio} = Circuits.GPIO.open(config.shutdown_override_gpio, :input)

    # case Circuits.GPIO.read(gpio) do
    #   1 -> :inspect
    #   0 -> :shutdown
    # end
    :inspect
  end
end
