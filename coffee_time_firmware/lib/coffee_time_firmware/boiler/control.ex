defmodule CoffeeTimeFirmware.Boiler.Control do
  use GenServer

  @moduledoc """
  Handles the PID loop for the boiler
  """

  defstruct context: nil

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    state = %__MODULE__{context: context}
    {:ok, state}
  end

  # def handle_continue(:duty_cycle, state) do
  # end
end
