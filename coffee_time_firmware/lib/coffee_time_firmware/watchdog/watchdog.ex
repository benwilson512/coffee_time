defmodule CoffeeTimeFirmware.Watchdog do
  @moduledoc """
  Identifies and logs faults, rebooting the pi if any are found.
  """

  use GenServer

  require Logger

  alias CoffeeTimeFirmware.Util

  import CoffeeTimeFirmware.Application, only: [name: 2]

  defstruct [
    :context,
    :fault,
    :fault_file_path,
    reboot_on_fault: true,
    time_limits: %{
      pump: :timer.seconds(60),
      grouphead_solenoid: :timer.seconds(60),
      refill_solenoid: :timer.seconds(60)
    },
    timers: %{}
  ]

  @doc """
  Clears a fault and then restarts the application.

  This is designed to be called manually as it normally reboots the pi.
  """
  def clear_fault!(context, opts \\ []) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:clear_fault)
    |> case do
      :cleared ->
        if Keyword.get(opts, :reboot, true) do
          :init.stop()
          :rebooting
        else
          :cleared
        end

      :no_fault ->
        :no_fault
    end
  end

  def get_fault(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:get_fault)
  end

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, config: config}) do
    state =
      %__MODULE__{
        context: context
      }
      |> struct!(config)
      |> populate_initial_fault_state

    CoffeeTimeFirmware.PubSub.subscribe(context, "*")

    {:ok, state}
  end

  def handle_call(:get_fault, _from, %{fault: fault} = state) do
    {:reply, fault, state}
  end

  def handle_call(:clear_fault, _from, %{fault: nil} = state) do
    {:reply, :no_fault, state}
  end

  def handle_call(:clear_fault, _from, state) do
    File.rm!(state.fault_file_path)
    {:reply, :cleared, state}
  end

  def handle_info({:waterflow_timeout, component}, state) do
    state = set_fault(state, "water flow component timeout: #{inspect(component)}")
    {:noreply, state}
  end

  def handle_info({:broadcast, :boiler_temp, val}, state) do
    state =
      if val > 130 do
        set_fault(state, "boiler over temp: #{val}")
      else
        state
      end

    {:noreply, state}
  end

  @state_toggles [
    pump: [on: :off],
    grouphead_solenoid: [open: :close],
    refill_solenoid: [open: :close]
  ]

  for {component, [{on_state, off_state}]} <- @state_toggles do
    def handle_info({:broadcast, unquote(component) = component, unquote(on_state)}, state) do
      handle_toggle_on(state, component)
    end

    def handle_info({:broadcast, unquote(component) = component, unquote(off_state)}, state) do
      handle_toggle_off(state, component)
    end
  end

  defp handle_toggle_on(state, component) do
    time = Map.fetch!(state.time_limits, component)
    timer = Util.send_after(self(), {:waterflow_timeout, component}, time)

    state = put_in(state.timers[component], timer)

    {:noreply, state}
  end

  def handle_toggle_off(state, component) do
    if timer = state.timers[component] do
      Process.cancel_timer(timer)
    end

    state = put_in(state.timers[component], nil)
    {:noreply, state}
  end

  def set_fault(state, fault) do
    fault = %__MODULE__.Fault{
      message: fault,
      occurred_at: DateTime.utc_now()
    }

    File.write!(state.fault_file_path, Jason.encode!(fault))

    if state.reboot_on_fault do
      :init.stop()
    end

    %{state | fault: fault}
  end

  def populate_initial_fault_state(state) do
    case File.read(state.fault_file_path) do
      {:ok, ""} ->
        state

      {:ok, contents} ->
        # intentionally assertive here. If the fault file exists and we can't make sense of it, then
        # who know's what's up, we should crash.
        fault =
          contents
          |> Jason.decode!()
          |> __MODULE__.Fault.from_json!()

        %{state | fault: fault}

      _ ->
        state
    end
  end
end
