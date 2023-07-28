defmodule CoffeeTime.ControlPanelDebugger do
  @moduledoc """
  Manages the front control panel of the device
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.Hardware
  alias CoffeeTime.Util

  require Logger

  defstruct [
    :context,
    gpio_pins: %{},
    interrupts: %{},
    timers: %{}
  ]

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params, name: name(context, __MODULE__))
  end

  def init(%{context: context}) do
    gpio_pins = setup_gpio_pins(context.hardware)
    interrupts = setup_interrupts(context.hardware, gpio_pins)

    data = %__MODULE__{
      context: context,
      gpio_pins: gpio_pins,
      interrupts: interrupts
    }

    {:ok, :ready, data}
  end

  ## Ready
  ###############

  def handle_event(:info, {:circuits_gpio, ref, _timestamp, _} = msg, :ready, data) do
    Logger.debug("#{inspect(msg)}")
    Process.sleep(100)
    gpio = data.gpio_pins[data.interrupts[ref]]
    Logger.debug("#{Circuits.GPIO.read(gpio)}")
    :keep_state_and_data
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
      {:ok, gpio} = CoffeeTime.Hardware.open_gpio(hardware, pin_name)
      {pin_name, gpio}
    end)
  end

  defp setup_interrupts(hardware, gpio_pins) do
    gpio_pins
    |> Map.take([:button1, :button2, :button3, :button4])
    |> Map.new(fn {label, gpio} ->
      interrupt_ref = Hardware.set_interrupts(hardware, gpio, :both)
      {interrupt_ref, label}
    end)
  end
end
