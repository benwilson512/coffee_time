defmodule CoffeeTimeFirmware.Boiler.Manager do
  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Boiler

  @moduledoc """
  Manages the Boiler state machine.

  Not entirely clear yet whether it, the DutyCycle process, or yet some third thing should
  be responsible for the PID loop. This process may be just fine, although obviously the PID math
  should get extracted to its own module.
  """

  defstruct target_temperature: 125, context: nil

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.cast(:boot)
  end

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    data = %__MODULE__{context: context}
    {:ok, :idle, data}
  end

  def handle_event(:cast, :boot, :idle, data) do
    Boiler.FillStatus.subscribe(data.context)

    next_state =
      case Boiler.FillStatus.check(data.context) do
        :full ->
          :boot_warmup

        :low ->
          # TODO: Go actually tell the pump to fill things
          :boot_fill
      end

    {:next_state, next_state, data}
  end

  ## Boot Fill
  ######################

  def handle_event(:info, {:broadcast, :fill_level_status, status}, :boot_fill, data) do
    # IO.puts("received #{status}")

    case status do
      :full ->
        {:next_state, :hold_temp, data}

      _ ->
        :keep_state_and_data
    end
  end

  ## Boot Warmup
  ######################

  # Using a transition callback here is really handy since there are multiple pathways into
  # this state.
  def handle_event(:event, _old_state, :boot_warmup, _data) do
    # TODO: Set the desired temp threshold in wherever controls that.
    :keep_state_and_data
  end

  def handle_event(:info, {:broadcast, :fill_level_status, :full}, :boot_warmup, _data) do
    :keep_state_and_data
  end

  def handle_event(:enter, old_state, new_state, data) do
    Logger.debug("""
    Boiler Transitioning from:
    Old: #{inspect(old_state)}
    New: #{inspect(new_state)}
    """)

    {:keep_state, data}
  end
end
