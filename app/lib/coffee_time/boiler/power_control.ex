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

  @default_reheat_offset_c -5
  @reheat_increment_c 0.5

  @db_key {__MODULE__, :target}

  defstruct target: 0,
            context: nil,
            target_duty_cycle: 0,
            hold_mode: :maintain,
            reheat_timer: nil,
            reheat_offset: @default_reheat_offset_c,
            reheat_iteration: :timer.seconds(30)

  def set_target(context, val) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call({:set_target, val})
  end

  def reheat_status(context) do
    context
    |> name(__MODULE__)
    |> GenStateMachine.call(:reheat_status)
  end

  def start_link(%{context: context}) do
    GenStateMachine.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    stored_target = CubDB.get(name(context, :db), @db_key)

    data = %__MODULE__{
      context: context,
      target: stored_target || 0,
      target_duty_cycle: 0
    }

    set_duty_cycle!(data)

    # No matter what we set the target duty cycle to 0 on boot. This gets overriden in the `:hold_target`
    # state if we are getting good readings from the boiler temp probe

    Measurement.Store.subscribe(data.context, :boiler_fill_status)
    Measurement.Store.subscribe(data.context, :boiler_temp)

    cond do
      CoffeeTime.Watchdog.get_fault(context) ->
        {:ok, :idle, data}

      Measurement.Store.get(data.context, :boiler_fill_status) == :full ->
        {:ok, :hold_target, data}

      true ->
        {:ok, :awaiting_boiler_fill, data}
    end
  end

  ## General Commands

  def handle_event({:call, from}, {:set_target, target}, _state, data) do
    Logger.info("Setting target: #{target}")

    {response, data} =
      if target < 128 do
        CubDB.put(name(data.context, :db), @db_key, target)
        {:ok, %{data | target: target}}
      else
        {{:error, :unsafe_target}, data}
      end

    {:keep_state, data, [{:reply, from, response}]}
  end

  def handle_event({:call, from}, :reheat_status, _state, data) do
    response = %{
      threshold: threshold(data),
      hold_mode: data.hold_mode
    }

    {:keep_state_and_data, [{:reply, from, response}]}
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
  def handle_event(:info, {:broadcast, :boiler_temp, val}, :hold_target, prev_data) do
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

  def handle_event(:info, {:broadcast, :boiler_fill_status, status}, :hold_target, data) do
    case status do
      :full ->
        :keep_state_and_data

      :low ->
        {:next_state, :awaiting_boiler_fill, data}
    end
  end

  ## General Handlers
  ##############################

  def handle_event(:info, {:reheat_increment, increment}, _, data) do
    data =
      data
      |> Map.update!(:reheat_offset, fn offset ->
        min(offset + increment, 0)
      end)
      |> cancel_reheat_timer
      |> case do
        %{reheat_offset: offset} = data when offset == 0 ->
          switch_to_maintain(data)

        data ->
          data
      end

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

  def adjust_hold_mode(%{hold_mode: :reheat} = data, value) do
    cond do
      # We are fully heated up, so switch out of reheat mode
      value >= data.target ->
        switch_to_maintain(data)

      data.reheat_offset == 0 ->
        switch_to_maintain(data)

      true ->
        data
    end
  end

  def adjust_hold_mode(data, value) do
    if value < offset_threshold(data) do
      Logger.notice("""
      Boiler entering reheat mode.
      """)

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
      :maintain -> data.target
      :reheat -> offset_threshold(data)
    end
  end

  defp offset_threshold(data) do
    data.target + data.reheat_offset
  end

  def maybe_set_reheat_timer(data) do
    case data do
      %{hold_mode: :reheat, reheat_timer: nil} ->
        timer =
          Util.send_after(
            self(),
            {:reheat_increment, @reheat_increment_c},
            data.reheat_iteration
          )

        %{data | reheat_timer: timer}

      _ ->
        data
    end
  end

  defp cancel_reheat_timer(data) do
    if timer = data.reheat_timer do
      Util.cancel_timer(timer)
    end

    %{data | reheat_timer: nil}
  end

  defp switch_to_maintain(data) do
    data = cancel_reheat_timer(data)

    %{
      data
      | hold_mode: :maintain,
        reheat_offset: @default_reheat_offset_c
    }
  end
end