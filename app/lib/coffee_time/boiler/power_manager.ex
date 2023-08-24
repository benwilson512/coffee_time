defmodule CoffeeTime.Boiler.PowerManager do
  @moduledoc """
  Manages changing the desired temp
  """

  # I'm not 100% convinced this needs to be a dedicated process vs the temp control and duty
  # cycle pids, but I'll sort that out at some point.

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTime.Application, only: [name: 2]
  import CompareChain

  alias CoffeeTime.PubSub
  alias CoffeeTime.Boiler
  alias CoffeeTime.Util

  # TODO: make these configurable without recompiling
  defstruct context: nil, ready_temp: 121, sleep_temp: 0

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

  def init(context) do
    data = %__MODULE__{
      context: context
    }

    PubSub.subscribe(context, :barista)

    config = lookup_config(context)
    now = DateTime.utc_now() |> DateTime.shift_zone!(timezone())
    state = init_state(config, now)

    set_quantum_jobs(context, config)

    {:ok, state, data}
  end

  defp init_state(config, now) do
    if sleep_time?(config, now) do
      :sleep
    else
      :ready
    end
  end

  def sleep_time?(config, now) do
    current_time = DateTime.to_time(now)

    case config[:power_saver_interval] do
      {from = %Time{}, to = %Time{}} ->
        # the awake time is between from and to, so sleep time is not awake time.
        not compare?(to <= current_time <= from, Time)

      _ ->
        false
    end
  end

  ## Ready
  ######################

  def handle_event(:enter, old_state, :ready, data) do
    Util.log_state_change(__MODULE__, old_state, :ready)
    Boiler.PowerControl.set_target(data.context, data.ready_temp)
    :keep_state_and_data
  end

  def handle_event({:call, from}, :sleep, :ready, data) do
    {:next_state, :sleep, data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :wake, :ready, _) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event(:info, _, :ready, _) do
    :keep_state_and_data
  end

  ## Sleeping
  ######################

  def handle_event(:enter, old_state, :sleep, data) do
    Util.log_state_change(__MODULE__, old_state, :sleep)
    Boiler.PowerControl.set_target(data.context, data.sleep_temp)

    :keep_state_and_data
  end

  # If we start doing something we should kick out of sleep and enter the ready
  # state
  def handle_event(:info, {:broadcast, :barista, {:program_start, _}}, :sleep, data) do
    {:next_state, :ready, data}
  end

  def handle_event(:info, {:broadcast, :barista, _}, :sleep, _) do
    :keep_state_and_data
  end

  def handle_event({:call, from}, :wake, :sleep, data) do
    {:next_state, :ready, data, {:reply, from, :ok}}
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

  ## Helpers
  ################

  defp set_quantum_jobs(context, config) do
    import Crontab.CronExpression

    case config[:power_saver_interval] do
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
end
