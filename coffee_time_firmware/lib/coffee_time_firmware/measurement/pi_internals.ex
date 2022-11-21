defmodule CoffeeTimeFirmware.Measurement.PiInternals do
  @moduledoc """
  Fetches the Pi CPU temp
  """

  use GenServer

  defstruct [:context, target_interval: 200]

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    state = %__MODULE__{context: context}
    set_timer(state)
    {:ok, state}
  end

  def handle_info(:query, state) do
    # We intentionally do this first so that we stick to an overall tick rate as close to our target
    # as possible.
    set_timer(state)

    temp = read_temp()

    # probably wrap in a try?
    CoffeeTimeFirmware.PubSub.broadcast(state.context, :cpu_temp, temp)

    {:noreply, state}
  end

  @temperature_file "/sys/class/thermal/thermal_zone0/temp"
  def read_temp() do
    @temperature_file
    |> File.read!()
    |> String.trim()
    |> String.to_integer()
    |> Kernel./(1000)
  end

  defp set_timer(state) do
    if state.target_interval < 75 do
      raise "Target interval should never be less than 75ms because it takes that long to read the sensor"
    else
      Process.send_after(self(), :query, state.target_interval)
    end
  end
end
