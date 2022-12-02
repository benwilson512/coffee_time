defmodule CoffeeTimeFirmware.WatchDog do
  use GenServer

  require Logger

  alias CoffeeTimeFirmware.Util

  @moduledoc """
  Identifies and logs faults, rebooting the pi if any are found.
  """

  defstruct [
    :context,
    :fault,
    :fault_file_path,
    time_limits: %{
      pump: :timer.seconds(60),
      grouphead_solenoid: :timer.seconds(60),
      refill_solenoid: :timer.seconds(60)
    },
    timers: %{}
  ]

  def start_link(%{context: context} = params) do
    GenServer.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(%{context: context, config: config}) do
    state =
      %__MODULE__{
        context: context
      }
      |> struct!(config)

    CoffeeTimeFirmware.PubSub.subscribe(context, "*")

    {:ok, state, {:continue, :maybe_fault}}
  end

  @water_flow_components [
    :pump,
    :grouphead_solenoid,
    :refill_solenoid
  ]

  def handle_info({:broadcast, component, :open}, state)
      when component in @water_flow_components do
    time = Map.fetch!(state.time_limits, component)
    timer = Util.send_after(self(), {:waterflow_timeout, component}, time)

    state = put_in(state.timers[component], timer)

    {:noreply, state}
  end

  def handle_info({:broadcast, component, :close}, state)
      when component in @water_flow_components do
    if timer = state.timers[component] do
      Process.cancel_timer(timer)
    end

    state = put_in(state.timers[component], nil)

    {:noreply, state}
  end

  def handle_info({:waterflow_timeout, component}, state) do
    # something
    record_fault!(state, "water flow component timeout: #{inspect(component)}")
    {:noreply, state}
  end

  def handle_info({:broadcast, :boiler_temp, val}, state) do
    if val > 130 do
      record_fault!(state, "boiler over temp")
    end

    {:noreply, state}
  end

  def record_fault!(state, fault) do
    File.write!(state.fault_file_path, fault)
    # probably should do something process tree related here too
  end
end
