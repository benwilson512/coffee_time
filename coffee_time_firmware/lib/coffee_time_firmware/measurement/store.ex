defmodule CoffeeTimeFirmware.Measurement.Store do
  @moduledoc """
  Handles storing measured values.

  Direct access to the sensors generally needs to be mediated by specific processes that are controlling
  GPIO state and other hardware internals.

  This process centralizes all recorded values to allow interested parties to access known temperatures at
  any interval they like. It also manages a pubsub mechanism for updates.
  """

  use GenServer

  defstruct [
    :context
  ]

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTimeFirmware.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    state = %__MODULE__{context: context}
    {:ok, state}
  end
end
