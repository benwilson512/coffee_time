defmodule CoffeeTimeFirmware.Barista do
  @moduledoc """
  Coordinates the various espresso machine sub-systems to accomplish various barista tasks.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  require Logger
  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Hydraulics
  alias CoffeeTimeFirmware.Util
  # alias CoffeeTimeFirmware.PubSub
  # alias CoffeeTimeFirmware.Measurement

  defstruct [
    :context,
    :db,
    :current_program,
    steps: [],
    timers: %{}
  ]

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:boot)
  end

  @spec save_program(any, CoffeeTimeFirmware.Barista.Program.t()) :: :ok | {:error, [String.t()]}
  def save_program(context, %__MODULE__.Program{name: name} = program) do
    case __MODULE__.Program.validate(program) do
      [] ->
        CubDB.put(name(context, :db), {:program, name}, program)
        :ok

      errors ->
        {:error, errors}
    end
  end

  def get_program(context, name) do
    CubDB.get(name(context, :db), {:program, name})
  end

  def list_programs(context) do
    # the min key max key stuff is a bit weird, but this is basically an artifact of
    # erlang term ordering. CubDB does everything via range queries, and
    # `1` is less than all atoms, and tuples are greater than all atoms. So if you want all keys that
    # are {:program, *} you just use 1 and {} to be less than and greater than all atoms respectively.
    context
    |> name(:db)
    |> CubDB.select(min_key: {:program, 1}, max_key: {:program, {}})
    |> Enum.to_list()
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

  def init(%{context: context}) do
    [{db, _}] = Registry.lookup(context.registry, :db)
    state = %__MODULE__{context: context, db: db}

    {:ok, :idle, state}
  end

  ## Idle

  def handle_event({:call, from}, :boot, :idle, data) do
    Boiler.TempControl.boot(data.context)
    Hydraulics.boot(data.context)
    {:next_state, :ready, data, {:reply, from, :done}}
  end

  ## Ready
  ##################

  def handle_event({:call, from}, {:run_program, program}, :ready, data) do
    {:next_state, {:executing, program}, data, {:reply, from, :ok}}
  end

  ## Executing
  ###############

  def handle_event(:enter, old_state, {:executing, program}, %{context: context} = data) do
    Util.log_state_change(__MODULE__, old_state, :executing)

    data = %{data | current_program: program, steps: program.steps}

    PubSub.broadcast(context, :barista, {:program_start, program})
    link!(context, Hydraulics)

    send(self(), {:advance_program, nil})

    {:keep_state, data}
  end

  def handle_event(:info, {:advance_program, timer}, {:executing, program}, data) do
    %{context: context} = data

    # Clear the timer if we were given one
    data = Map.update!(data, :timers, &Map.delete(&1, timer))

    case advance_program(data) do
      %{steps: []} = data ->
        unlink!(context, Hydraulics)
        PubSub.broadcast(context, :barista, {:program_done, program})
        {:next_state, :ready, %{data | current_program: nil}}

      data ->
        {:keep_state, data}
    end
  end

  def handle_event({:call, from}, {:run_program, _}, {:executing, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  ## General
  ###############

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  ## Program Execution Loop
  #########################

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

      {:wait, :timer, time} = step ->
        timer = Util.send_after(self(), {:advance_program, step}, time)

        data
        |> Map.update!(:timers, fn timers ->
          Map.put(timers, step, timer)
        end)
        |> Map.replace!(:steps, rest)
    end
  end

  ## Helpers
  ######################

  defp link!(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    Process.link(pid)
  end

  defp unlink!(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    Process.unlink(pid)
  end
end
