defmodule CoffeeTimeFirmware.Boiler do
  alias __MODULE__

  @moduledoc """
  Handles steam boiler logic.

  The logic for the steam boiler is broken into three components:

  - `Boiler.DutyCycle` acts as a software PWM to control the actual GPIO to the solid state relay
  - `Boiler.Control` is the PID cycle that translates the boiler temperature into a duty cycle
  - `Boiler.Breakers` watches for various problems and will trip "circuit breakers" that require manual reset.

  The choice to split these into three distinct GenServers came from the need to manage several independent timers.
  The DutyCycle timer in particular has to be pretty strict since it controls the actual amount of power sent to the
  heating element. The Circuit breakers need to poll a bunch of different things, and that activity needs to not get
  in the way of the duty cycle or the PID cycle.

  # Circuit Breakers

  The only thing that is slightly wonky about this approach is that there's a bit of a weird relationship between
  the DutyCycle and Breakers modules. On the one hand the duty cycle process needs to be directly responsible
  for setting the GPIO writes so that we can have strict control over the timing. However if we want to trip the circuit
  breakers it'd be nice not need to rely on the DutyCycle process state.

  OH I need a relay.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {__MODULE__.DutyCycle, []},
      {__MODULE__.Breakers, []},
      {__MODULE__.Control, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
