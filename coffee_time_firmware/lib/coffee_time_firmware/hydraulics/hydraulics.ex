defmodule CoffeeTimeFirmware.Hydraulics do
  @moduledoc """
  Handles controlling the solenoids and water pump.

  ## Smart Functionality

  The Hydraulics subsystem monitors the fill level of the steam boiler and will automatically
  initiate a refill process if it isn't busy doing something else.

  ## "Dumb" Functionality

  As far as opening the solenoids or turning on the pump, this module has relatively simple responsibilities.
  It won't let you turn on the pump if there isn't a solenoid open since that just needlessly pressurizes
  the system, but it doesn't provide anything fancy as far as running the pump for a certain amount of
  time. All the "smarts" sit over in `CoffeeTimeFirmware.Barista`.

  ## General Design Decisions

  This is intentionally separate from the actual
  front panel controls on the espresso machine. It's better to have an API that can be called independent
  of the actual interface, whether that's push buttons, the command line (remote shell), or a future
  web page.

  I'm also avoiding the temptation to overdesign this and have it parameterized nicely for multiple
  group heads, boilers, and pumps. I have 1 boiler, 1 pump, and 1 group head. I also have no idea
  how machines with multiples of those are plumped. If I ever add another boiler to my machine I'll
  figure things out at that point.

  ## Internal notes

  This is a :gen_statem process. The approach I'm using is that changes to solenoids and the pump
  are all enacted at the `:enter` clauses for the states. This means that any state can for example
  `{:next_state, :ready, data}` and rely on the `:ready` state to close all the solenoids and turn
  off the pump without having to worry about turning the pump off from various different states.
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
    |> GenStateMachine.call(:boot)
  end

  def halt(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:halt)
  end

  @doc """
  Open a solenoid
  """
  def open_solenoid(context, solenoid) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:open_solenoid, solenoid})
  end

  def activate_pump(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:activate_pump)
  end

  def deactivate_pump(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:deactivate_pump)
  end

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context}) do
    data = %__MODULE__{
      context: context,
      gpio_pins: setup_gpio_pins(context.hardware)
    }

    Measurement.Store.subscribe(data.context, :boiler_fill_status)

    cond do
      CoffeeTimeFirmware.Watchdog.get_fault(context) ->
        {:ok, :idle, data}

      Measurement.Store.fetch!(data.context, :boiler_fill_status) == :low ->
        {:ok, :boiler_filling, data}

      true ->
        {:ok, :ready, data}
    end
  end

  ## Idle
  ####################

  # No actions are supported in the idle state. The fault should be cleared and the machine rebooted
  def handle_event(:info, _, :idle, _data) do
    :keep_state_and_data
  end

  ## Ready
  ##################

  def handle_event(:enter, old_state, :ready, data) do
    Util.log_state_change(__MODULE__, old_state, :ready)

    pump_off!(data)
    # NOTE TO self: It may be a good idea to add a small delay between turning the pump off
    # and closing the solenoids. Doing it "instantly" might produce a water hammer effect.
    # Need to test.
    refill_solenoid_close!(data)
    grouphead_solenoid_close!(data)

    :keep_state_and_data
  end

  def handle_event({:call, from}, {:open_solenoid, solenoid}, :ready, data) do
    {:next_state, {:holding_solenoid, solenoid}, data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :activate_pump, :ready, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :no_open_solenoid}}}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, :low}, :ready, data) do
    {:next_state, :boiler_filling, data}
  end

  ## Boiler Filling
  ##################

  def handle_event(:enter, old_state, :boiler_filling, data) do
    Util.log_state_change(__MODULE__, old_state, :boiler_filling)

    refill_solenoid_open!(data)
    pump_on!(data)

    {:keep_state, data}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :boiler_filling, data) do
    case status do
      :low ->
        :keep_state_and_data

      :full ->
        {:next_state, :ready, data}
    end
  end

  def handle_event({:call, from}, {:open_solenoid, _}, :boiler_filling, _) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  def handle_event({:call, from}, :activate_pump, :boiler_filling, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  def handle_event({:call, from}, :halt, :boiler_filling, _) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  ## Solenoid Management
  #####################

  def handle_event(:enter, old_state, {:holding_solenoid, solenoid}, data) do
    Util.log_state_change(__MODULE__, old_state, :holding_solenoid)

    case solenoid do
      :grouphead ->
        grouphead_solenoid_open!(data)
    end

    :keep_state_and_data
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, :low}, {:holding_solenoid, _}, _) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, {:open_solenoid, _}, {:holding_solenoid, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :busy}}}
  end

  def handle_event({:call, from}, :activate_pump, {:holding_solenoid, _}, data) do
    pump_on!(data)
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :deactivate_pump, {:holding_solenoid, _}, data) do
    pump_off!(data)
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :halt, {:holding_solenoid, _}, data) do
    {:next_state, :ready, data, {:reply, from, :ok}}
  end

  ## Other
  ##############

  def handle_event(:info, {:broadcast, :boiler_fill_status, :full}, _, _) do
    :keep_state_and_data
  end

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

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
end
