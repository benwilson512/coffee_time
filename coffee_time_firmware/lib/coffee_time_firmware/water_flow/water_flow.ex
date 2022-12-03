defmodule CoffeeTimeFirmware.WaterFlow do
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

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  require Logger
  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Hardware
  alias CoffeeTimeFirmware.Util

  defstruct [
    :context,
    gpio_pins: %{}
  ]

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.cast(:boot)
  end

  @doc """
  Run water to the espresso group head.

  ```
  # 20 seconds
  drive_grouphead(context, {:timer, 20000})
  # 20 seconds with a 3 second delay before the pump starts
  drive_grouphead(context, {:timer, 20000, pump_delay: 3000})
  ```

  TOOD: Support `{:flow_ticks, n}`.
  """
  def drive_grouphead(context, mode) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:drive_grouphead, mode})
  end

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    data = %__MODULE__{
      context: context,
      gpio_pins: setup_gpio_pins(context.hardware)
    }

    {:ok, :idle, data}
  end

  ## Idle
  ####################

  def handle_event(:cast, :boot, :idle, data) do
    Measurement.Store.subscribe(data.context, :boiler_fill_status)

    next_state =
      case Measurement.Store.fetch!(data.context, :boiler_fill_status) do
        :full ->
          :ready

        :low ->
          :boiler_filling
      end

    {:next_state, next_state, data}
  end

  def handle_event({:call, from}, _, :idle, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :not_yet_booted}}}
  end

  def handle_event(_, _, :idle, _data) do
    :keep_state_and_data
  end

  ## Ready
  ##################

  def handle_event({:call, from}, {:drive_grouphead, mode}, :ready, data) do
    case mode do
      {:timer, duration} ->
        Util.send_after(self(), :halt_grouphead, duration)
    end

    {:next_state, :driving_grouphead, data, {:reply, from, :ok}}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, :low}, :ready, data) do
    {:next_state, :boiler_filling, data}
  end

  ## Boiler Filling
  ##################

  def handle_event(:enter, old_state, :boiler_filling = new_state, data) do
    log_state_transition(old_state, new_state)

    refill_solenoid_open!(data)
    pump_on!(data)

    {:keep_state, data}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :boiler_filling, data) do
    case status do
      :low ->
        :keep_state_and_data

      :full ->
        refill_solenoid_close!(data)
        pump_off!(data)

        {:next_state, :ready, data}
    end
  end

  def handle_event({:call, from}, {:drive_grouphead, _}, :boiler_filling, _) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  ## Grouphead Driving
  #####################

  def handle_event(:enter, _, :driving_grouphead, data) do
    grouphead_solenoid_open!(data)
    pump_on!(data)
    :keep_state_and_data
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, :low}, :driving_grouphead, _) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, {:drive_grouphead, _}, :driving_grouphead, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  def handle_event(:info, :halt_grouphead, :driving_grouphead, data) do
    pump_off!(data)
    grouphead_solenoid_close!(data)
    {:next_state, :ready, data}
  end

  ## Other
  ##############

  def handle_event(:info, {:broadcast, :boiler_fill_status, :full}, _, _) do
    :keep_state_and_data
  end

  def handle_event(:enter, old_state, new_state, data) do
    log_state_transition(old_state, new_state)

    {:keep_state, data}
  end

  ## These should probably get extracted to Hardware maybe?

  defp pump_on!(%{context: context, gpio_pins: %{pump: pump}}) do
    Hardware.write_gpio(context.hardware, pump, 0)
    PubSub.broadcast(context, :pump, :on)
  end

  defp pump_off!(%{context: context, gpio_pins: %{pump: pump}}) do
    Hardware.write_gpio(context.hardware, pump, 1)
    PubSub.broadcast(context, :pump, :off)
  end

  defp grouphead_solenoid_open!(%{context: context, gpio_pins: %{grouphead_solenoid: gpio}}) do
    Hardware.write_gpio(context.hardware, gpio, 0)
    PubSub.broadcast(context, :grouphead_solenoid, :open)
  end

  defp grouphead_solenoid_close!(%{context: context, gpio_pins: %{grouphead_solenoid: gpio}}) do
    Hardware.write_gpio(context.hardware, gpio, 1)
    PubSub.broadcast(context, :grouphead_solenoid, :close)
  end

  defp refill_solenoid_open!(%{context: context, gpio_pins: %{refill_solenoid: gpio}}) do
    Hardware.write_gpio(context.hardware, gpio, 0)
    PubSub.broadcast(context, :refill_solenoid, :open)
  end

  defp refill_solenoid_close!(%{context: context, gpio_pins: %{refill_solenoid: gpio}}) do
    Hardware.write_gpio(context.hardware, gpio, 1)
    PubSub.broadcast(context, :refill_solenoid, :close)
  end

  defp setup_gpio_pins(hardware) do
    Map.new([:grouphead_solenoid, :refill_solenoid, :pump], fn pin_name ->
      {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(hardware, pin_name)
      {pin_name, gpio}
    end)
  end

  defp log_state_transition(old_state, new_state) do
    Logger.debug("""
    Boiler Transitioning from:
    Old: #{inspect(old_state)}
    New: #{inspect(new_state)}
    """)
  end
end
