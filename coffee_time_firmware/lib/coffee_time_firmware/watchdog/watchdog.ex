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
    deadline: %{},
    healthcheck: %{},
    threshold: %{},
    reboot_on_fault: true,
    timers: %{}
  ]

  @doc """
  Clears a fault and then restarts the application.

  This is designed to be called manually as it normally reboots the pi.
  """
  def clear_fault!(context, opts \\ []) do
    context
    |> name(__MODULE__)
    |> GenServer.call(:clear_fault)
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
    |> GenServer.call(:get_fault)
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

    state =
      if !state.fault do
        CoffeeTimeFirmware.PubSub.subscribe(context, "*")
        init_healthchecks(state)
      else
        Logger.error("""
        Booting into fault state:
        #{inspect(state.fault)}
        """)

        state
      end

    {:ok, state}
  end

  defp init_healthchecks(state) do
    Enum.reduce(state.healthcheck, state, fn {k, _}, state ->
      set_timer(state, :healthcheck, k)
    end)
  end

  def handle_call(:get_fault, _from, %{fault: fault} = state) do
    {:reply, fault, state}
  end

  def handle_call(:clear_fault, _from, %{fault: nil} = state) do
    {:reply, :no_fault, state}
  end

  def handle_call(:clear_fault, _from, state) do
    File.rm!(state.fault_file_path)
    {:reply, :cleared, state, {:continue, :restart_self}}
  end

  def handle_continue(:restart_self, state) do
    {:stop, :normal, state}
  end

  def handle_info({:timer_expired, {type, key}}, state) do
    message =
      case type do
        :deadline -> "Deadline failed timeout: #{inspect(key)}"
        :healthcheck -> "Healthcheck failed timeout: #{inspect(key)}"
      end

    {:stop, :fault, set_fault(state, message)}
  end

  @healthcheck_and_threshold [
    :boiler_temp,
    :cpu_temp
  ]

  def handle_info({:broadcast, key, val}, state) when key in @healthcheck_and_threshold do
    threshold = Map.fetch!(state.threshold, key)

    if val > threshold do
      {:stop, :fault,
       set_fault(
         state,
         "Threshold exceeded: The value of #{key}, #{val}, exceeds #{threshold}"
       )}
    else
      state =
        state
        |> cancel_timer(:healthcheck, key)
        |> set_timer(:healthcheck, key)

      {:noreply, state}
    end
  end

  def handle_info({:broadcast, :cpu_temp, val}, state) do
    if val > 130 do
      {:stop, :fault, set_fault(state, "boiler over temp: #{val}")}
    else
      state =
        state
        |> cancel_timer(:healthcheck, :cpu_temp)
        |> set_timer(:healthcheck, :cpu_temp)

      {:noreply, state}
    end
  end

  def handle_info({:broadcast, :boiler_fill_status, _}, state) do
    state =
      state
      |> cancel_timer(:healthcheck, :boiler_fill_status)
      |> set_timer(:healthcheck, :boiler_fill_status)

    {:noreply, state}
  end

  @state_toggles [
    pump: [on: :off],
    grouphead_solenoid: [open: :close],
    refill_solenoid: [open: :close]
  ]

  for {component, [{on_state, off_state}]} <- @state_toggles do
    def handle_info({:broadcast, unquote(component) = component, unquote(on_state)}, state) do
      {:noreply, set_timer(state, :deadline, component)}
    end

    def handle_info({:broadcast, unquote(component) = component, unquote(off_state)}, state) do
      {:noreply, cancel_timer(state, :deadline, component)}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp set_timer(state, type, key) do
    time =
      case state do
        %{
          ^type => %{^key => time}
        } ->
          time

        _ ->
          raise "No timer configuration found for #{type}, #{key}"
      end

    timer = Util.send_after(self(), {:timer_expired, {type, key}}, time)

    put_in(state.timers[{type, key}], timer)
  end

  defp cancel_timer(state, type, key) do
    if timer = state.timers[{type, key}] do
      Process.cancel_timer(timer)
    end

    put_in(state.timers[{type, key}], nil)
  end

  def set_fault(%{fault: nil} = state, fault) do
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

  def set_fault(%{fault: existing_fault} = state, new_fault) do
    Logger.error("""
    Faults stacking up
    Existing: #{inspect(existing_fault)}
    New: #{inspect(new_fault)}
    """)

    state
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
