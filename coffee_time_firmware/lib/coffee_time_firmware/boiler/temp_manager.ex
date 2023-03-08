defmodule CoffeeTimeFirmware.Boiler.TempManager do
  @moduledoc """
  Manages changing the desired temp
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Util

  # TODO: make these configurable without recompiling
  defstruct context: nil, ready_temp: 121, sleep_temp: 105

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

  def init(context) do
    data = %__MODULE__{
      context: context
    }

    PubSub.subscribe(context, :barista)

    set_quantum_jobs(context)

    {:ok, :ready, data}
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

  defp set_quantum_jobs(context) do
    import Crontab.CronExpression

    # sleep job
    CoffeeTimeFirmware.Scheduler.new_job()
    |> Quantum.Job.set_timezone("America/New_York")
    |> Quantum.Job.set_name(:sleep)
    # 6pm ET
    |> Quantum.Job.set_schedule(~e[0 18 * * *])
    |> Quantum.Job.set_task(fn -> sleep(context) end)
    |> CoffeeTimeFirmware.Scheduler.add_job()

    # wake job
    CoffeeTimeFirmware.Scheduler.new_job()
    |> Quantum.Job.set_timezone("America/New_York")
    |> Quantum.Job.set_name(:wake)
    # at 5:30 am ET
    |> Quantum.Job.set_schedule(~e[30 5 * * *])
    |> Quantum.Job.set_task(fn -> wake(context) end)
    |> CoffeeTimeFirmware.Scheduler.add_job()
  end
end
