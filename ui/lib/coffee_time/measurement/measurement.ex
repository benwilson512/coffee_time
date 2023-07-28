defmodule CoffeeTime.Measurement do
  @moduledoc """
  Centralizes general sensor measurements.

  Various logic depends on being able to fetch the current value of various sensor measurements,
  as well as subscribe to updates.

  Importantly this module is only tracking inputs that you might consider "general" about the espresso
  machine and its operating environment. Inputs specific to control buttons are still handled specifically
  by their related module.
  """

  use Supervisor

  def start_link(%{context: context} = params) do
    Supervisor.start_link(__MODULE__, params,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  @impl true
  def init(params) do
    # Don't really like this pattern. I like having them as values passed in and not globals
    # but this is still an awkward API.
    params =
      Map.put_new(params, :intervals, %{
        __MODULE__.BoilerTempProbe => %{read_interval: 500},
        __MODULE__.BoilerFillStatus => %{
          idle_read_interval: :timer.seconds(5),
          refill_read_interval: :timer.seconds(1)
        },
        __MODULE__.CpuTemp => %{read_interval: 2000}
      })

    children = [
      {__MODULE__.Store, params},
      {__MODULE__.BoilerFillStatus, params},
      {__MODULE__.Max31865Server, [rtd_wires: 4, spi_device_cs_pin: 0]},
      {__MODULE__.BoilerTempProbe, params},
      {__MODULE__.CpuTemp, params},
      {__MODULE__.OneWireSensor,
       Map.merge(params, %{
         name: :ssr_temp,
         read_interval: 5000
       })},
      {CoffeeTime.Measurement.FlowMeter, params}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
