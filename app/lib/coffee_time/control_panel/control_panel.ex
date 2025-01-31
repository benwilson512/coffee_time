defmodule CoffeeTime.ControlPanel do
  @moduledoc """
  Manages the front control panel of the device
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  import CoffeeTime.Application, only: [db: 1, name: 2]

  alias CoffeeTime.Barista
  alias CoffeeTime.Hardware
  alias CoffeeTime.PubSub
  alias CoffeeTime.Util

  require Logger

  defstruct [
    :context,
    :config,
    gpio_pins: %{},
    interrupts: %{},
    timers: %{}
  ]

  def dump_config(context) do
    context
    |> db
    |> CubDB.select(min_key: {:control_panel, 1}, max_key: {:control_panel, {}})
    |> Enum.to_list()
    |> Enum.map(fn
      {{:control_panel, button}, spec} -> {button, spec}
    end)
  end

  def set_button(context, logical_button, {:program, program_name}) do
    db = db(context)
    key = {:control_panel, logical_button}

    case Barista.get_program(context, program_name) do
      %Barista.Program{} ->
        new = {:program, program_name}
        old = CubDB.get(db, key)
        CubDB.put(db, key, new)
        {:ok, old: old, new: new}

      other ->
        {:error, {:program_not_found, name: program_name, returned: other}}
    end
  end

  def start_link(%{context: context} = params) do
    GenStateMachine.start_link(__MODULE__, params, name: name(context, __MODULE__))
  end

  def init(%{context: context, config: config}) do
    gpio_pins = setup_gpio_pins(context.hardware)
    interrupts = setup_interrupts(context.hardware, gpio_pins)

    data = %__MODULE__{
      context: context,
      config: config,
      gpio_pins: gpio_pins,
      interrupts: interrupts
    }

    PubSub.subscribe(context, :barista)

    cond do
      CoffeeTime.Watchdog.get_fault(context) ->
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

  def handle_event(:info, _, {:fault, _}, _data) do
    :keep_state_and_data
  end

  ## Ready
  ###############

  def handle_event(:info, {:circuits_gpio, _interrupt_ref, _timestamp, 0}, :ready, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, {:circuits_gpio, interrupt_ref, timestamp, 1}, :ready, data) do
    if press_confirmed?(interrupt_ref, data) do
      {:next_state, {:press, interrupt_ref, timestamp}, data}
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:broadcast, :barista, _}, :ready, _data) do
    :keep_state_and_data
  end

  ## Press

  def handle_event(:info, {:circuits_gpio, ref, timestamp, 0}, {:press, ref, _}, data) do
    logical_button = Map.fetch!(data.interrupts, ref)

    with {:program, program} <- CubDB.get(db(data.context), {:control_panel, logical_button}),
         :ok <- Barista.run_program(data.context, program) do
      {:next_state, {:watching, %{ref: ref, timestamp: timestamp, program: program}}, data}
    else
      nil ->
        Logger.warning("""
        No button action defined for #{inspect(logical_button)} (GPIO:#{inspect(ref)})
        """)

        {:next_state, :ready, data}

      error ->
        Logger.error("""
        Invalid button config: #{inspect(error)}
        """)

        {:next_state, :ready, data}
    end
  end

  def handle_event(:info, {:circuits_gpio, ref, _, val}, {:press, _, _}, _) do
    Logger.warning("Ignoring press from GPIO #{inspect(ref)} #{inspect(val)}")
    :keep_state_and_data
  end

  ## Watching
  ###############
  def handle_event(:enter, old_state, {:watching, _} = new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  def handle_event(:info, {:circuits_gpio, ref, _, 1}, {:watching, %{ref: ref}}, data) do
    if press_confirmed?(ref, data) do
      :ok = Barista.halt(data.context)
      {:next_state, :ready, data}
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:circuits_gpio, _ref, _timestamp, _}, {:watching, _}, _) do
    :keep_state_and_data
  end

  def handle_event(:info, {:broadcast, :barista, :ready}, {:watching, _}, data) do
    {:next_state, :ready, data}
  end

  def handle_event(:info, {:broadcast, :barista, _}, {:watching, _}, _) do
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

  defp press_confirmed?(interrupt_ref, data) do
    Process.sleep(100)
    gpio = data.gpio_pins[data.interrupts[interrupt_ref]]
    Hardware.read_gpio(data.context.hardware, gpio) == 1
  end
end
