defmodule CoffeeTimeFirmware.Boiler.TempControl do
  @moduledoc """
  Manages the Boiler state machine.

  Not entirely clear yet whether it, the DutyCycle process, or yet some third thing should
  be responsible for the PID loop. This process may be just fine, although obviously the PID math
  should get extracted to its own module.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Measurement
  alias CoffeeTimeFirmware.Boiler
  alias CoffeeTimeFirmware.Util

  defstruct target_temperature: 0,
            context: nil,
            target_duty_cycle: 0,
            hold_mode: :maintain,
            temp_reheat_timer: nil,
            temp_reheat_offset: 5,
            temp_reheat_duration: :timer.minutes(2)

  def set_target_temp(context, temp) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:set_target_temp, temp})
  end

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    stored_temp = CubDB.get(name(context, :db), :target_temp)

    data = %__MODULE__{
      context: context,
      target_temperature: stored_temp || 0,
      target_duty_cycle: 0
    }

    set_duty_cycle!(data)

    # No matter what we set the target duty cycle to 0 on boot. This gets overriden in the `:hold_temp`
    # state if we are getting good readings from the boiler temp probe

    Measurement.Store.subscribe(data.context, :boiler_fill_status)
    Measurement.Store.subscribe(data.context, :boiler_temp)

    cond do
      CoffeeTimeFirmware.Watchdog.get_fault(context) ->
        {:ok, :idle, data}

      Measurement.Store.get(data.context, :boiler_fill_status) == :full ->
        {:ok, :hold_temp, data}

      true ->
        {:ok, :awaiting_boiler_fill, data}
    end
  end

  ## General Commands

  def handle_event({:call, from}, {:set_target_temp, temp}, _state, data) do
    {response, data} =
      if temp < 128 do
        CubDB.put(name(data.context, :db), :target_temp, temp)
        {:ok, %{data | target_temperature: temp}}
      else
        {{:error, :unsafe_temp}, data}
      end

    {:keep_state, data, [{:reply, from, response}]}
  end

  ## Idle
  ####################

  # No actions are supported in the idle state. The fault should be cleared and the machine rebooted
  def handle_event(:info, _, :idle, _data) do
    :keep_state_and_data
  end

  ## Boiler Fill
  ######################

  def handle_event(:enter, old_state, :awaiting_boiler_fill, data) do
    Util.log_state_change(__MODULE__, old_state, :awaiting_boiler_fill)
    data = %{data | target_duty_cycle: 0}
    set_duty_cycle!(data)

    {:keep_state, data}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :awaiting_boiler_fill, data) do
    case status do
      :full ->
        {:next_state, :hold_temp, data}

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:info, {:broadcast, _, _}, :awaiting_boiler_fill, _) do
    :keep_state_and_data
  end

  ## Temp hold logic
  ######################

  # Boiler temp update
  def handle_event(:info, {:broadcast, :boiler_temp, val}, :hold_temp, prev_data) do
    # TODO: This is a super basic threshold style logic, to be later replaced by a PID.
    # At that point this will certainly get extracted from this module, and may end up
    # being its own process.
    data =
      prev_data
      |> adjust_hold_mode(val)
      |> adjust_target_duty_cycle(val)

    if data.target_duty_cycle != prev_data.target_duty_cycle do
      set_duty_cycle!(data)
    end

    {:keep_state, data}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :hold_temp, data) do
    case status do
      :full ->
        :keep_state_and_data

      :low ->
        {:next_state, :awaiting_boiler_fill, data}
    end
  end

  ## General Handlers
  ##############################

  def handle_event(:info, :reheat_complete, _, data) do
    if timer = data.temp_reheat_timer do
      Util.cancel_timer(timer)
    end

    data = %{data | hold_mode: :maintain, temp_reheat_timer: nil}

    {:keep_state, data}
  end

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  defp set_duty_cycle!(%{target_duty_cycle: cycle, context: context}) do
    Logger.info("Changing duty cycle: #{cycle}")
    :ok = Boiler.DutyCycle.set(context, cycle)
  end

  def adjust_hold_mode(%{hold_mode: :reheat} = data, _) do
    data
  end

  def adjust_hold_mode(data, value) do
    reheat_threshold = data.target_temperature - data.temp_reheat_offset

    if value < reheat_threshold do
      %{data | hold_mode: :reheat}
    else
      data
    end
  end

  def adjust_target_duty_cycle(data, value) do
    if value < threshold(data) do
      %{data | target_duty_cycle: 10}
    else
      data
      |> Map.replace(:target_duty_cycle, 0)
      |> maybe_set_reheat_timer()
    end
  end

  def threshold(data) do
    case data.hold_mode do
      :maintain -> data.target_temperature
      :reheat -> data.target_temperature - data.temp_reheat_offset
    end
  end

  def maybe_set_reheat_timer(data) do
    case data do
      %{hold_mode: :reheat, temp_reheat_timer: nil} ->
        timer = Util.send_after(self(), :reheat_complete, data.temp_reheat_duration)
        %{data | temp_reheat_timer: timer}

      _ ->
        data
    end
  end
end
