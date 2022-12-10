defmodule CoffeeTimeFirmware.ControlPanel do
  @moduledoc """
  Manages the front control panel of the device
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Hardware
  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Util

  require Logger

  defstruct [
    :context,
    :config,
    gpio_pins: %{},
    timers: %{}
  ]

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params, name: name(context, __MODULE__))
  end

  def init(%{context: context, config: config}) do
    data = %__MODULE__{
      context: context,
      config: config,
      gpio_pins: setup_gpio_pins(context.hardware)
    }

    PubSub.subscribe(context, :barista)

    cond do
      CoffeeTimeFirmware.Watchdog.get_fault(context) ->
        {:ok, {:fault, :on}, data}

      true ->
        {:ok, :ready, data}
    end
  end

  ## Fault State
  ###############

  # In this state we do an all LED slow blink

  def handle_event(:enter, _, {:fault, :on}, data) do
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led1, 1)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led2, 1)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led3, 1)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led4, 1)

    Util.send_after(self(), :blink, data.config.fault_blink_rate)
    {:keep_state, data}
  end

  def handle_event(:info, :blink, {:fault, :on}, data) do
    {:next_state, {:fault, :off}, data}
  end

  def handle_event(:enter, _, {:fault, :off}, data) do
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led1, 0)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led2, 0)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led3, 0)
    Hardware.write_gpio(data.context.hardware, data.gpio_pins.led4, 0)

    Util.send_after(self(), :blink, data.config.fault_blink_rate)
    {:keep_state, data}
  end

  def handle_event(:info, :blink, {:fault, :off}, data) do
    {:next_state, {:fault, :on}, data}
  end

  ## General
  ###############

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  ## Helpers
  ###############

  defp setup_gpio_pins(hardware) do
    Map.new([:button1, :button2, :button3, :button4, :led1, :led2, :led3, :led4], fn pin_name ->
      {:ok, gpio} = CoffeeTimeFirmware.Hardware.open_gpio(hardware, pin_name)
      {pin_name, gpio}
    end)
  end
end
