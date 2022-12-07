defmodule CoffeeTimeFirmware.Barista.Program do
  @moduledoc """
  Describes an Espresso machine program.

  At the moment this is a very simple structure that just lets you run a solenoid for
  either a certain amount of time, or for a certain volume of water. You can configure pump delays.

  In time there are grand plans for this to support fancier features, but I'm trying to not overcomplicate
  it yet.
  """
  @enforce_keys [:name]
  defstruct [
    :name,
    :grouphead_duration,
    pump_delay: {:timer, 0}
  ]
end
