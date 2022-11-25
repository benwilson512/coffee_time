defmodule CoffeeTimeFirmware.Boiler do
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

  def start_link(%{context: context}) do
    Supervisor.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  @impl true
  def init(context) do
    children = [
      {__MODULE__.TempProbe, %{context: context}},
      {__MODULE__.FillLevel, %{context: context}},
      {__MODULE__.DutyCycle, %{context: context}},
      {__MODULE__.Control, %{context: context}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
