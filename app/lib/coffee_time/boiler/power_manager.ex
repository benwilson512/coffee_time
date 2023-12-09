defmodule CoffeeTime.Boiler.PowerManager do
  @moduledoc """
  Manages changing the desired temp

  Roughly speaking the boiler operations in 3 power modes:

  1) Sleep: It's asleep and there is no power
  2) Idle: It's hot enough to be pressurized and make espresso, but is too low
  for practical steaming
  3) Active: Nice and hot for steaming.

  Sleep is controlled via a schedule. You can also kick it out of sleep mode by
  running any barista program or manually via the API.

  Idle converts to active by flushing steam through the steam wand. You need to
  do this anyway to flush condensate, so this tells the `PowerManager` that you
  want steam.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTime.Application, only: [name: 2]
  import CompareChain

  alias CoffeeTime.PubSub
  alias CoffeeTime.Boiler
  alias CoffeeTime.Util
  alias CoffeeTime.Measurement

  alias __MODULE__.Config

  defstruct context: nil,
            config: %Config{},
            prev_pressure: 0,
            active_timer: nil,
            refill_timer: nil

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def wake(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:wake)
  end

  def sleep(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:sleep)
  end

  def lookup_config(context) do
    CubDB.get(name(context, :db), :boiler_power_manager)
  end

  def __set_config__(context, config) do
    CubDB.put(name(context, :db), :boiler_power_manager, config)
  end

  def replace_config(context, key, value) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:replace_config, key, value})
  end

  def init(context) do
    config = init_config(context)

    data = %__MODULE__{
      context: context,
      config: config
    }

    now = DateTime.utc_now() |> DateTime.shift_zone!(timezone())
    state = init_state(config, now)

    set_quantum_jobs(context, config)

    {:ok, state, data}
  end

  defp init_state(config, now) do
    if sleep_time?(config, now) do
      :sleep
    else
      :idle
    end
  end

  def sleep_time?(config, now) do
    current_time = DateTime.to_time(now)

    case config.power_saver_interval do
      {from = %Time{}, to = %Time{}} ->
        # the awake time is between from and to, so sleep time is not awake time.
        not compare?(to <= current_time <= from, Time)

      _ ->
        false
    end
  end

  ## Idle
  ######################

  def handle_event(:enter, old_state, :idle, data) do
    Util.log_state_change(__MODULE__, old_state, :idle)

    Boiler.PowerControl.set_target(data.context, data.config.idle_pressure)

    data = reset_timers_and_subs(data)

    PubSub.subscribe(data.context, :refill_solenoid)
    Measurement.Store.subscribe(data.context, :boiler_pressure)

    {:keep_state, %{data | prev_pressure: 0}}
  end

  def handle_event(:info, {:broadcast, :boiler_pressure, val}, :idle, prev_data) do
    data = %{prev_data | prev_pressure: val}

    cond do
      # We just refilled, we need to give it a moment to reheat
      data.refill_timer ->
        {:keep_state, data}

      in_use_pressure_drop?(prev_data, val) ->
        {:next_state, :active, data}

      # I sort of want to get rid of this, but it plays a helpful
      # role in upgrading the target to the active level on boot.
      # We could have wake and init both jump to active, which might be fine.
      # However we really need to sort out deduped subscriptions to make
      # that work properly.
      val < data.config.active_trigger_threshold ->
        {:next_state, :active, data}

      true ->
        {:keep_state, data}
    end
  end

  def handle_event(:info, {:broadcast, :refill_solenoid, :open}, :idle, data) do
    # In theory we could have a timer going already
    data = Util.cancel_self_timer(data, :refill_timer)
    {:keep_state, %{data | refill_timer: :pending}}
  end

  def handle_event(:info, {:broadcast, :refill_solenoid, :close}, :idle, data) do
    timer = Util.send_after(self(), :refilled, data.config.refill_grace_period)
    {:keep_state, %{data | refill_timer: timer}}
  end

  def handle_event(:info, :refilled, :idle, data) do
    {:keep_state, %{data | refill_timer: nil}}
  end

  def handle_event(:info, _, :idle, _) do
    :keep_state_and_data
  end

  ## Active
  ######################

  def handle_event(:enter, old_state, :active, data) do
    Util.log_state_change(__MODULE__, old_state, :active)
    active_target = data.config.active_pressure
    Boiler.PowerControl.set_target(data.context, active_target)

    :keep_state_and_data
  end

  def handle_event(:info, {:broadcast, :boiler_pressure, val}, :active, prev_data) do
    new_data = %{prev_data | prev_pressure: val}

    new_data =
      cond do
        # if we experience a notable drop in pressure
        # then that means we are in active use and we should
        # cancel the timer until we are back to temp
        in_use_pressure_drop?(prev_data, val) ->
          Util.cancel_self_timer(new_data, :active_timer)

        # if we get above the target value then we can start
        # the timer for returning to idle. `start_timer` is
        # idempotent and will not change a timer if one is already
        # running
        val >= new_data.config.active_pressure ->
          Util.start_self_timer(
            new_data,
            :active_timer,
            :deactivate,
            new_data.config.active_duration
          )

        true ->
          new_data
      end

    {:keep_state, new_data}
  end

  def handle_event(:info, :deactivate, :active, data) do
    {:next_state, :idle, data}
  end

  ## Sleeping
  ######################

  def handle_event(:enter, old_state, :sleep, data) do
    Util.log_state_change(__MODULE__, old_state, :sleep)

    Boiler.PowerControl.set_target(data.context, data.config.sleep_pressure)

    data = reset_timers_and_subs(data)
    PubSub.subscribe(data.context, :barista)

    {:keep_state, data}
  end

  # If we start doing something we should kick out of sleep and enter the idle
  # state
  def handle_event(:info, {:broadcast, :barista, {:program_start, _}}, :sleep, data) do
    {:next_state, :idle, data}
  end

  def handle_event(:info, {:broadcast, :barista, _}, :sleep, _) do
    :keep_state_and_data
  end

  def handle_event({:call, from}, :wake, :sleep, data) do
    {:next_state, :idle, data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :sleep, :sleep, _) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  ## General
  ##########

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  def handle_event({:call, from}, {:replace_config, key, value}, _, data) do
    old_config = data.config
    new_config = Map.replace(old_config, key, value)
    data = %{data | config: new_config}

    __set_config__(data.context, new_config)

    reply = [
      old: Map.fetch!(old_config, key),
      new: Map.fetch!(new_config, key)
    ]

    {:repeat_state, data, {:reply, from, reply}}
  end

  def handle_event({:call, from}, :sleep, _, data) do
    Measurement.Store.unsubscribe(data.context, :boiler_pressure)
    {:next_state, :sleep, data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :wake, _, _) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event(:info, msg, _, _) do
    Logger.warning("""
    unexpected message

    #{inspect(msg)}
    """)

    :keep_state_and_data
  end

  ## Helpers
  ################

  defp reset_timers_and_subs(%{context: context} = data) do
    Measurement.Store.unsubscribe(data.context, :boiler_pressure)
    PubSub.unsubscribe(context, :barista)
    PubSub.unsubscribe(context, :refill_solenoid)

    data
    |> Util.cancel_self_timer(:active_timer)
    |> Util.cancel_self_timer(:refill_timer)
  end

  defp set_quantum_jobs(context, config) do
    import Crontab.CronExpression

    case config.power_saver_interval do
      {from = %Time{}, to = %Time{}} ->
        set_job(:sleep, ~e[#{from.minute} #{from.hour} * * *], fn -> sleep(context) end)
        set_job(:wake, ~e[#{to.minute} #{to.hour} * * *], fn -> wake(context) end)

      _ ->
        :ok
    end
  end

  defp set_job(name, cron_spec, fun) do
    CoffeeTime.Scheduler.new_job()
    |> Quantum.Job.set_timezone(timezone())
    |> Quantum.Job.set_name(name)
    |> Quantum.Job.set_schedule(cron_spec)
    |> Quantum.Job.set_task(fun)
    |> CoffeeTime.Scheduler.add_job()
  end

  defp timezone() do
    Application.fetch_env!(:coffee_time, :timezone)
  end

  defp cancel_timer(data) do
    if ref = data.active_timer do
      Util.cancel_timer(ref)
      %{data | active_timer: nil}
    else
      data
    end
  end

  defp in_use_pressure_drop?(prev_data, val) do
    prev_data.prev_pressure - val > 75
  end

  defp init_config(context) do
    config = lookup_config(context) || %Config{}
    # this is terrible
    config = struct(Config, Map.take(config, Map.keys(%Config{}) -- [:__struct__]))
    __set_config__(context, config)
    config
  end
end
