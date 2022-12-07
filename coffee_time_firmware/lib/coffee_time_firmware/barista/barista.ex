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

  def put_preset(context, key, %__MODULE__.Preset{} = preset) do
    CubDB.put(name(context, :db), {:preset, key}, preset)
  end

  def run_preset(context, key) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:run_preset, key})
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

  def handle_event({:call, from}, {:run_preset, key}, :ready, data) do
    case CubDB.get(data.db, {:preset, key}) do
      nil ->
        {:keep_state_and_data, {:reply, from, {:error, :preset_not_found}}}

      preset ->
        {:next_state, {:running_preset, preset}, data, {:reply, from, :ok}}
    end
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
