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
    deadline: %{},
    healthcheck: %{},
    threshold: %{},
    allowances: %{},
    reboot_on_fault: true,
    timers: %{}
  ]

  @type fault_type :: :deadline | :healthcheck | :threshold

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

  def fault!(context, reason) do
    context
    |> name(__MODULE__)
    |> GenServer.cast({:put_fault, reason})
  end

  @doc """
  Adjust a watchdog trigger to allow for some new value or threshold

  Primarily used by the hydraulics subsystem to allow the refill solenoid to
  stay on longer than normal to fill the boiler. It's also often useful when
  operating in remote console.

  Only one allowance of any given type and key are allowed at a time. Allowances
  are tied to the process which requests the allowance. This provices a nice
  safety mechanism in general, and in particular for the remote console
  scenario in that once the user exits the shell any allowances are automatically
  reset.
  """
  @spec acquire_allowance(Context.t(), fault_type, atom, term) :: :ok | {:error, term}
  def acquire_allowance(context, type, key, value, opts \\ []) do
    context
    |> name(__MODULE__)
    |> GenServer.call({:acquire_allowance, type, key, value, opts[:owner] || self()})
  end

  @spec release_allowance(Context.t(), fault_type, atom) :: :ok | {:error, term}
  def release_allowance(context, type, key) do
    context
    |> name(__MODULE__)
    |> GenServer.call({:release_allowance, type, key})
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

    if state.fault do
      CoffeeTimeFirmware.PubSub.broadcast(context, :watchdog, :fault_state)
    else
      CoffeeTimeFirmware.PubSub.broadcast(context, :watchdog, :ready)
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
    File.rm!(fault_file_path(state.context))
    {:reply, :cleared, state, {:continue, :restart_self}}
  end

  def handle_call({:acquire_allowance, type, key, value, owner}, _from, state) do
    case Map.fetch(state.allowances, {type, key}) do
      {:ok, %{owner: existing_owner}} ->
        {:reply, {:error, {:already_taken, existing_owner}}, state}

      _ ->
        state = do_allowance(state, type, key, value, owner)
        {:reply, :ok, state}
    end
  end

  def handle_call({:release_allowance, type, key}, {from_pid, _}, state) do
    case undo_allowance(state, type, key, from_pid) do
      {:ok, state} ->
        {:reply, :ok, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_cast({:put_fault, reason}, state) do
    {:stop, :fault, set_fault(state, reason)}
  end

  def handle_continue(:restart_self, state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    state =
      state.allowances
      # If we needed LOLSPEED here we could store an inverted index of ref to
      # {type, key} but I mean really, 99.999% of the time there's gonna be
      # just 1 allowance, and there's an upper bound of like 12. No point.
      |> Enum.filter(fn {_, allowance} ->
        allowance.ref == ref
      end)
      |> Enum.reduce(state, fn {{type, key}, _}, state ->
        {:ok, state} = undo_allowance(state, type, key, pid)
        state
      end)

    {:noreply, state}
  end

  def handle_info({:timer_expired, {type, key}}, state) do
    message =
      case type do
        :deadline -> "Deadline failed timeout: #{inspect(key)}"
        :healthcheck -> "Healthcheck failed timeout: #{inspect(key)}"
      end

    {:stop, :fault, set_fault(state, message)}
  end

  @healthchecks [
    :boiler_temp,
    :cpu_temp,
    :boiler_fill_status
  ]

  def handle_info({:broadcast, key, val}, state) when key in @healthchecks do
    threshold = Map.get(state.threshold, key)

    if threshold && val > threshold do
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
    case state do
      %{
        ^type => %{^key => time}
      } ->
        timer = Util.send_after(self(), {:timer_expired, {type, key}}, time)

        put_in(state.timers[{type, key}], timer)

      _ ->
        state
    end
  end

  defp cancel_timer(state, type, key) do
    if timer = state.timers[{type, key}] do
      Util.cancel_timer(timer)
      flush_timer(type, key)
    end

    put_in(state.timers[{type, key}], nil)
  end

  defp replace_timer(state, key, type) do
    # If a timer already exists for a given type
    if timer = state.timers[{type, key}] do
      Util.cancel_timer(timer)
      flush_timer(type, key)

      put_in(state.timers[{type, key}], nil)
      |> set_timer(type, key)
    else
      state
    end
  end

  defp flush_timer(type, key) do
    receive do
      {:timer_expired, {^type, ^key}} ->
        :ok
    after
      0 ->
        :ok
    end
  end

  def set_fault(%{fault: nil} = state, fault) do
    fault = %__MODULE__.Fault{
      message: fault,
      occurred_at: DateTime.utc_now()
    }

    File.write!(fault_file_path(state.context), Jason.encode!(fault))

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
    case File.read(fault_file_path(state.context)) do
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

  defp do_allowance(state, type, key, value, owner) do
    previous_value =
      state
      |> Map.fetch!(type)
      |> Map.fetch!(key)

    allowance = %{
      new_value: value,
      previous_value: previous_value,
      owner: owner,
      ref: Process.monitor(owner),
      type: type,
      key: key,
      value: value
    }

    state
    |> replace_config(type, key, value)
    |> Map.update!(:allowances, fn allowances ->
      Map.put(allowances, {type, key}, allowance)
    end)
    |> replace_timer(type, key)
  end

  defp undo_allowance(state, type, key, from_pid) do
    case Map.pop(state.allowances, {type, key}) do
      {nil, _} ->
        {:error, :not_found}

      {allowance, allowances} ->
        if allowance.owner != from_pid do
          Logger.warning("""
          Allowance removed by different pid.
          Owner: #{inspect(allowance.owner)}
          Caller pid: #{inspect(from_pid)}

          Allowance: #{inspect(allowance)}
          """)
        end

        state =
          %{state | allowances: allowances}
          |> replace_config(type, key, allowance.previous_value)
          |> Map.replace!(:allowances, allowances)
          |> replace_timer(key, type)

        {:ok, state}
    end
  end

  defp replace_config(state, type, key, value) do
    state
    |> Map.update!(type, fn config ->
      Map.replace!(config, key, value)
    end)
  end

  def fault_file_path(%{data_dir: dir}) do
    Path.join(dir, "fault.json")
  end
end
