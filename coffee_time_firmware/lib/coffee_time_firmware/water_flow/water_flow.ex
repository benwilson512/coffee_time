defmodule CoffeeTimeFirmware.WaterFlow do
  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  require Logger
  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Measurement

  @moduledoc """
  Handles controlling the solenoids and water pump.

  This is intentionally separate from the actual
  front panel controls on the espresso machine. It's better to have an API that can be called independent
  of the actual interface, whether that's push buttons, the command line (remote shell), or a future
  web page.

  I'm also avoiding the temptation to overdesign this and have it parameterized nicely for multiple
  group heads, boilers, and pumps. I have 1 boiler, 1 pump, and 1 group head. I also have no idea
  how machines with multiples of those are plumped. If I ever add another boiler to my machine I'll
  figure things out at that point.
  """

  defstruct [:context]

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.cast(:boot)
  end

  def refill_boiler(_context) do
  end

  def pull_espresso(_context) do
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
    Measurement.Store.subscribe(data.context, :boiler_fill_status)

    next_state =
      case Measurement.Store.fetch!(data.context, :boiler_fill_status) do
        :full ->
          :ready

        :low ->
          # This process does not enact boiler fill. Rather it relies on the water
          # flow logic to refill things.
          :boiler_filling
      end

    {:next_state, next_state, data}
  end

  def handle_event(:enter, old_state, :boiler_filling = new_state, %{context: context} = data) do
    log_state_transition(old_state, new_state)

    CoffeeTimeFirmware.Hardware.write_gpio(context.hardware, data.refill_solenoid_gpio, 0)
    CoffeeTimeFirmware.Hardware.write_gpio(context.hardware, data.pump_gpio, 0)

    PubSub.broadcast(context, :pump_status, :on)

    {:keep_state, data}
  end

  def handle_event(:enter, old_state, new_state, data) do
    log_state_transition(old_state, new_state)

    {:keep_state, data}
  end

  defp log_state_transition(old_state, new_state) do
    Logger.debug("""
    Boiler Transitioning from:
    Old: #{inspect(old_state)}
    New: #{inspect(new_state)}
    """)
  end
end
