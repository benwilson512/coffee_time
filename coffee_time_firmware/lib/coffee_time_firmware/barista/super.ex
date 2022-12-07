defmodule CoffeeTimeFirmware.Barista.Super do
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
    Supervisor.start_link(__MODULE__, params,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  @impl true
  def init(%{context: context} = params) do
    cubdb_opts = [
      name: CoffeeTimeFirmware.Application.name(context, :db),
      data_dir: Path.join(context.data_dir, "barista")
    ]

    children = [
      {CubDB, cubdb_opts},
      {CoffeeTimeFirmware.Barista, params}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
