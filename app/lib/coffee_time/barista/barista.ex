defmodule CoffeeTime.Barista do
  @moduledoc """
  Coordinates the various espresso machine sub-systems to accomplish various barista tasks.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTime.Application, only: [name: 2, db: 1]

  require Logger
  alias CoffeeTime.PubSub
  alias CoffeeTime.Hydraulics
  alias CoffeeTime.Util
  # alias CoffeeTime.PubSub
  # alias CoffeeTime.Measurement

  defstruct [
    :context,
    :current_program,
    steps: [],
    timers: %{}
  ]

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  @spec save_program(any, CoffeeTime.Barista.Program.t()) :: :ok | {:error, [String.t()]}
  def save_program(context, %__MODULE__.Program{name: name} = program) do
    case __MODULE__.Program.validate(program) do
      [] ->
        CubDB.put(db(context), {:program, name}, program)
        :ok

      errors ->
        {:error, errors}
    end
  end

  def get_program(context, name) do
    CubDB.get(db(context), {:program, name})
  end

  def list_programs(context) do
    # the min key max key stuff is a bit weird, but this is basically an artifact of
    # erlang term ordering. CubDB does everything via range queries, and
    # `1` is less than all atoms, and tuples are greater than all atoms. So if you want all keys that
    # are {:program, *} you just use 1 and {} to be less than and greater than all atoms respectively.
    context
    |> db
    |> CubDB.select(min_key: {:program, 1}, max_key: {:program, {}})
    |> Enum.map(fn {_, program} -> program end)
  end

  @doc """
  Run a Barista program.

  This function takes either a `%Barista.Program{}` struct, or the name of a saved
  program.
  """

  def run_program(context, %__MODULE__.Program{} = program) do
    case __MODULE__.Program.validate(program) do
      [] ->
        context
        |> name(__MODULE__)
        |> GenStateMachine.call({:run_program, program})

      errors ->
        {:error, errors}
    end
  end

  def run_program(context, name) do
    case get_program(context, name) do
      nil ->
        {:error, :not_found}

      %__MODULE__.Program{name: ^name} = program ->
        run_program(context, program)

      other ->
        raise """
        Program store corrupted!
        Name: #{inspect(name)}
        Program #{inspect(other)}
        """
    end
  end

  @spec halt(atom | %{:root => any, optional(any) => any}) :: any
  def halt(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:halt)
  end

  def init(%{context: context}) do
    state = %__MODULE__{context: context}

    # This module doesn't need an `:idle` state since it doesn't directly control anything. If you ask
    # the barista process to try to run a program while the hydraulics or temp control is idle due to
    # a fault it will simply crash. No need to manage it in a fancy way.
    {:ok, :ready, state}
  end

  ## Ready
  ##################

  def handle_event(:enter, old_state, :ready, data) do
    Util.log_state_change(__MODULE__, old_state, :ready)

    PubSub.unsubscribe(data.context, :flow_pulse)

    :keep_state_and_data
  end

  def handle_event({:call, from}, {:run_program, program}, :ready, data) do
    {:next_state, {:executing, program}, data, {:reply, from, :ok}}
  end

  def handle_event(:info, {:broadcast, _, _}, :ready, _data) do
    :keep_state_and_data
  end

  ## Executing
  ###############

  def handle_event(:enter, old_state, {:executing, program}, %{context: context} = data) do
    Util.log_state_change(__MODULE__, old_state, :executing)

    data = %{data | current_program: program, steps: [{:resume, :timer, :start} | program.steps]}

    link!(context, Hydraulics)

    PubSub.broadcast(context, :barista, {:program_start, program})
    PubSub.subscribe(context, :flow_pulse)
    send(self(), {:advance_program, :start})

    {:keep_state, data}
  end

  def handle_event(:info, msg, {:executing, program}, data) do
    Logger.debug("Received: #{inspect(msg)} #{inspect(data.steps)}")

    case {data.steps, msg} do
      {[{:resume, :timer, time} | steps], {:advance_program, time}} ->
        handle_resume(program, %{data | steps: steps})

      {[{:resume, :flow_pulse, 1} | steps], {:broadcast, :flow_pulse, {1, _time}}} ->
        handle_resume(program, %{data | steps: steps})

      {[{:resume, :flow_pulse, n} | steps], {:broadcast, :flow_pulse, {1, _time}}} ->
        {:keep_state, %{data | steps: [{:resume, :flow_pulse, n - 1} | steps]}}

      _ ->
        {:keep_state, data}
    end
  end

  def handle_event({:call, from}, {:run_program, _}, {:executing, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  def handle_event({:call, from}, :halt, {:executing, program}, data) do
    :ok = Hydraulics.halt(data.context)
    for {_, timer} <- data.timers, do: Util.cancel_timer(timer)

    PubSub.broadcast(data.context, :barista, {:program_done, program})

    {:next_state, :ready, %{data | timers: %{}}, {:reply, from, :ok}}
  end

  ## General
  ###############

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  def handle_event({:call, from}, :halt, _, _) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  ## Program Execution Loop
  #########################

  defp handle_resume(program, %{context: context} = data) do
    case advance_program(data) do
      %{steps: []} = data ->
        unlink!(context, Hydraulics)
        PubSub.broadcast(context, :barista, {:program_done, program})

        {:next_state, :ready, %{data | current_program: nil}}

      data ->
        {:keep_state, data}
    end
  end

  def advance_program(%{steps: []} = data) do
    data
  end

  def advance_program(%{steps: [step | rest], context: context} = data) do
    Logger.debug("""
    Executing step: #{inspect(step)} | #{data.current_program.name}
    """)

    case step do
      {:solenoid, solenoid, :open} ->
        :ok = Hydraulics.open_solenoid(context, solenoid)
        advance_program(%{data | steps: rest})

      {:pump, :on} ->
        :ok = Hydraulics.activate_pump(context)
        advance_program(%{data | steps: rest})

      {:pump, :off} ->
        :ok = Hydraulics.deactivate_pump(context)
        advance_program(%{data | steps: rest})

      {:hydraulics, :halt} ->
        :ok = Hydraulics.halt(context)
        advance_program(%{data | steps: rest})

      {:wait, :flow_pulse, val} ->
        steps = [{:resume, :flow_pulse, val} | rest]

        %{data | steps: steps}

      {:wait, :timer, time} ->
        timer = Util.send_after(self(), {:advance_program, time}, time)

        steps = [{:resume, :timer, time} | rest]

        data
        |> Map.update!(:timers, fn timers ->
          Map.put(timers, step, timer)
        end)
        |> Map.replace!(:steps, steps)
    end
  end

  ## Helpers
  ######################

  defp link!(context, name) do
    pid = GenServer.whereis(CoffeeTime.Application.name(context, name))
    Process.link(pid)
  end

  defp unlink!(context, name) do
    pid = GenServer.whereis(CoffeeTime.Application.name(context, name))
    Process.unlink(pid)
  end
end
