defmodule CoffeeTimeFirmware.Barista do
  @moduledoc """
  Coordinates the various espresso machine sub-systems to accomplish various barista tasks.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  require Logger
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Hydraulics
  # alias CoffeeTimeFirmware.PubSub
  # alias CoffeeTimeFirmware.Measurement

  defstruct [
    :context,
    :db
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

  def save_program(context, name, %__MODULE__.Program{} = preset) do
    CubDB.put(name(context, :db), {:program, name}, preset)
  end

  def get_program(context, name) do
    CubDB.get(name(context, :db), {:program, name})
  end

  @doc """
  Run a Barista program.

  This function takes either a `%Barista.Program{}` struct, or the name of a saved
  program.
  """

  def run_program(context, %__MODULE__.Program{} = program) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:run_program, program})
  end

  def run_program(context, name) do
    case get_program(context, name) do
      nil ->
        {:error, :not_found}

      %__MODULE__.Program{} = program ->
        run_program(context, program)

      other ->
        raise """
        Program store corrupted!
        Name: #{inspect(name)}
        ProgramL #{inspect(other)}
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

  ## General
  ###############

  def handle_event(:enter, old_state, new_state, data) do
    Logger.debug("""
    Barista Transitioning from:
    Old: #{inspect(old_state)}
    New: #{inspect(new_state)}
    """)

    {:keep_state, data}
  end
end
