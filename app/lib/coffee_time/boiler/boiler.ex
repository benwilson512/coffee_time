defmodule CoffeeTime.Boiler do
  @moduledoc """
  Handles steam boiler logic.

  The logic for the steam boiler is broken into three components:

  - `Boiler.DutyCycle` acts as a software PWM to control the actual GPIO to the solid state relay
  - `Boiler.Control` is the PID cycle that translates the boiler temperature into a duty cycle

  The choice to split these into three distinct GenServers came from the need to manage several independent timers.
  The DutyCycle timer in particular has to be pretty strict since it controls the actual amount of power sent to the
  heating element.
  """

  use Supervisor

  def start_link(%{context: context} = params) do
    if CoffeeTime.Watchdog.get_fault(context) do
      :ignore
    else
      Supervisor.start_link(__MODULE__, params,
        name: CoffeeTime.Application.name(context, __MODULE__)
      )
    end
  end

  @impl true
  def init(params) do
    # Don't really like this pattern. I like having them as values passed in and not globals
    # but this is still an awkward API.
    params =
      Map.put_new(params, :intervals, %{
        __MODULE__.DutyCycle => %{write_interval: 100}
      })

    children = [
      {__MODULE__.DutyCycle, params},
      {__MODULE__.PowerControl, params},
      {__MODULE__.PowerManager, params}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
