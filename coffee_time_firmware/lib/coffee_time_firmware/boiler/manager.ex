defmodule CoffeeTimeFirmware.Boiler.Manager do
  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  @moduledoc """
  Manages the Boiler state machine.

  Not entirely clear yet whether it, the DutyCycle process, or yet some third thing should
  be responsible for the PID loop. This process may be just fine, although obviously the PID math
  should get extracted to its own module.
  """

  defstruct context: nil

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:boot)
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

  def handle_event({:call, from}, :boot, :idle, data) do
    {:next_state, :booting, [{:reply, from, data}]}
  end

  def handle_event(:enter, event, state, data) do
    binding() |> IO.inspect(label: :entering_event)
    {:next_state, state, data}
  end
end
