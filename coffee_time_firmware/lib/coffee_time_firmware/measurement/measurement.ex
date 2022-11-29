defmodule CoffeeTimeFirmware.Measurement do
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
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  @impl true
  def init(params) do
    # Don't really like this pattern. I like having them as values passed in and not globals
    # but this is still an awkward API.
    params =
      Map.put_new(params, :intervals, %{
        __MODULE__.BoilerTempProbe => %{read_interval: 500},
        __MODULE__.BoilerFillStatus => %{idle_read_interval: 1000, refill_read_interval: 100},
        __MODULE__.PiInternals => %{read_interval: 2000}
      })

    children = [
      {__MODULE__.Store, params},
      {__MODULE__.BoilerFillStatus, params},
      {__MODULE__.BoilerTempProbe, params},
      {__MODULE__.PiInternals, params}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
