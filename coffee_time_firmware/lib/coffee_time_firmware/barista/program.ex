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
    steps: [],
    remaining_steps: []
  ]

  def validate(program) do
    []
    |> validate_any_steps(program)
    |> validate_final_step(program)

    # |> validate_pump_sequence
  end

  def validate_any_steps(errors, program) do
    case program.steps do
      [] -> ["Must include at least one step" | errors]
      _ -> errors
    end
  end

  def validate_final_step(errors, program) do
    case List.last(program.steps) do
      nil -> errors
      {:wait, _} -> ["Final step cannot be a wait" | errors]
      _ -> errors
    end
  end
end
