defmodule CoffeeTimeFirmware.Boiler.TempManager do
  @moduledoc """
  Manages changing the desired temp
  """

  # I'm not 100% convinced this needs to be a dedicated process vs the temp control and duty
  # cycle pids, but I'll sort that out at some point.

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTimeFirmware.Application, only: [name: 2]
  import CompareChain

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Util

  # TODO: make these configurable without recompiling
  defstruct context: nil, ready_temp: 121, sleep_temp: 0

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
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
    CubDB.get(name(context, :db), __MODULE__)
  end

  def init(context) do
    data = %__MODULE__{
      context: context
    }

    PubSub.subscribe(context, :barista)

    config = lookup_config(context)
    apply_config(data, config)

    set_quantum_jobs(context, config)

    {:ok, :ready, data}
  end

  defp apply_config(data, config) do
    if sleeping_now?(config) do
      {:ok, :sleep, data}
    else
      {:ok, :read, data}
    end
  end

  defp sleeping_now?(config) do
    now = DateTime.utc_now() |> DateTime.to_time()

    case config[:power_saver_interval] do
      {from = %Time{}, to = %Time{}} ->
        compare?(now <= from or to <= now)

      _ ->
        false
    end
  end

  ## Ready
  ######################

  def handle_event(:enter, old_state, :ready, data) do
    Util.log_state_change(__MODULE__, old_state, :ready)
    Boiler.TempControl.set_target_temp(data.context, data.ready_temp)
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
    Boiler.TempControl.set_target_temp(data.context, data.sleep_temp)

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
        set_job(:wake, ~e[#{to.minute} #{to.hour} * * *], fn -> sleep(context) end)

      _ ->
        :ok
    end
  end

  defp set_job(name, cron_spec, fun) do
    CoffeeTimeFirmware.Scheduler.new_job()
    |> Quantum.Job.set_timezone("America/New_York")
    |> Quantum.Job.set_name(name)
    |> Quantum.Job.set_schedule(cron_spec)
    |> Quantum.Job.set_task(fun)
    |> CoffeeTimeFirmware.Scheduler.add_job()
  end
end
