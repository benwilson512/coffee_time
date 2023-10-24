defmodule CoffeeTime.Boiler.PowerControl do
  @moduledoc """
  Manages the Boiler state machine.

  Not entirely clear yet whether it, the DutyCycle process, or yet some third thing should
  be responsible for the PID loop. This process may be just fine, although obviously the PID math
  should get extracted to its own module.
  """

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require Logger

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.Measurement
  alias CoffeeTime.Boiler
  alias CoffeeTime.Util

  defstruct target: 0,
            context: nil,
            target_duty_cycle: 0

  def set_target(context, val) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:set_target, val})
  end

  def get_target(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:get_target)
  end

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    data = %__MODULE__{
      context: context,
      target: 0,
      target_duty_cycle: 0
    }

    set_duty_cycle!(data)

    # No matter what we set the target duty cycle to 0 on boot. This gets overriden in the `:hold_target`
    # state if we are getting good readings from the boiler temp probe

    Measurement.Store.subscribe(data.context, :boiler_fill_status)
    Measurement.Store.subscribe(data.context, :boiler_pressure)

    cond do
      Measurement.Store.get(data.context, :boiler_fill_status) == :full ->
        {:ok, :hold_target, data}

      true ->
        {:ok, :awaiting_boiler_fill, data}
    end
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
        {:next_state, :hold_target, data}

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:info, {:broadcast, _, _}, :awaiting_boiler_fill, _) do
    :keep_state_and_data
  end

  ## Target hold logic
  ######################

  # Boiler temp update
  def handle_event(:info, {:broadcast, :boiler_pressure, val}, :hold_target, prev_data) do
    # TODO: This is a super basic threshold style logic, to be later replaced by a PID.
    # At that point this will certainly get extracted from this module, and may end up
    # being its own process.
    data =
      adjust_target_duty_cycle(prev_data, val)

    if data.target_duty_cycle != prev_data.target_duty_cycle do
      set_duty_cycle!(data)
    end

    {:keep_state, data}
  end

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :hold_target, data) do
    case status do
      :full ->
        :keep_state_and_data

      :low ->
        {:next_state, :awaiting_boiler_fill, data}
    end
  end

  ## General Commands

  def handle_event({:call, from}, {:set_target, nil}, _state, data) do
    data = %{data | target: nil, target_duty_cycle: 0}
    set_duty_cycle!(data)
    {:next_state, :idle, data, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, {:set_target, target}, _state, data) do
    Logger.info("Setting target: #{target}")

    {response, data} =
      if valid_target?(target) do
        {:ok, %{data | target: target}}
      else
        {{:error, :unsafe_target}, data}
      end

    {:keep_state, data, [{:reply, from, response}]}
  end

  def handle_event({:call, from}, :get_target, _state, data) do
    {:keep_state_and_data, [{:reply, from, data.target}]}
  end

  ## General Handlers
  ##############################

  def handle_event(:enter, old_state, new_state, data) do
    Util.log_state_change(__MODULE__, old_state, new_state)

    {:keep_state, data}
  end

  defp set_duty_cycle!(%{target_duty_cycle: cycle, context: context}) do
    Logger.info("Changing duty cycle: #{cycle}")
    :ok = Boiler.DutyCycle.set(context, cycle)
  end

  def adjust_target_duty_cycle(data, value) do
    if value < data.target do
      %{data | target_duty_cycle: 10}
    else
      %{data | target_duty_cycle: 0}
    end
  end

  defp valid_target?(target) do
    target < 15000
  end
end
