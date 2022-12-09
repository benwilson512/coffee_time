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

  defstruct target_temperature: 110, context: nil, target_duty_cycle: 0

  def boot(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:boot)
  end

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
    data = %__MODULE__{context: context}
    {:ok, :idle, data}
  end

  def handle_event({:call, from}, :boot, :idle, data) do
    Measurement.Store.subscribe(data.context, :boiler_fill_status)
    Measurement.Store.subscribe(data.context, :boiler_temp)

    next_state =
      case Measurement.Store.fetch!(data.context, :boiler_fill_status) do
        :full ->
          :hold_temp

        :low ->
          # This process does not enact boiler fill. Rather it relies on the water
          # flow logic to refill things.
          :awaiting_boiler_fill
      end

    {:next_state, next_state, data, {:reply, from, :ok}}
  end

  ## General Commands

  def handle_event({:call, from}, {:set_target_temp, temp}, _state, data) do
    {response, data} =
      if temp < 128 do
        {:ok, %{data | target_temperature: temp}}
      else
        {{:error, :unsafe_temp}, data}
      end

    {:keep_state, data, [{:reply, from, response}]}
  end

  ## Boiler Fill
  ######################

  def handle_event(:enter, old_state, :awaiting_boiler_fill, data) do
    Util.log_state_change(__MODULE__, old_state, :awaiting_boiler_fill)
    data = %{data | target_duty_cycle: 0}
    set_duty_cycle!(data)

    {:keep_state, %{data | target_duty_cycle: 0}}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :awaiting_boiler_fill, data) do
    # IO.puts("received #{status}")

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
      if val < prev_data.target_temperature do
        %{prev_data | target_duty_cycle: 10}
      else
        %{prev_data | target_duty_cycle: 0}
      end

    if data.target_duty_cycle != prev_data.target_duty_cycle do
      set_duty_cycle!(data)
    end

    {:keep_state, data}
  end

  # Fill level status
  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :hold_temp, data) do
    case status do
      :full ->
        :keep_state_and_data

      :low ->
        {:next_state, :awaiting_boiler_fill, data}
    end
  end

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  defp set_duty_cycle!(%{target_duty_cycle: cycle, context: context}) do
    Logger.info("Changing duty cycle: #{cycle}")
    :ok = Boiler.DutyCycle.set(context, cycle)
  end
end
