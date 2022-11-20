defmodule CoffeeTimeFirmware.Measurement do
  alias __MODULE__

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

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {__MODULE__.Store, []},
      {__MODULE__.BoilerProbe, []},
      {__MODULE__.PiInternals, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # defdelegate fetch_temp(), to: __MODULE__.Store
end
