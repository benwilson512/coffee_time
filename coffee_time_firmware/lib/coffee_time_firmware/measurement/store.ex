defmodule CoffeeTimeFirmware.Measurement.Store do
  alias __MODULE__

  @moduledoc """
  Handles storing measured values.

  Direct access to the sensors generally needs to be mediated by specific processes that are controlling
  GPIO state and other hardware internals.

  This process centralizes all recorded values to allow interested parties to access known temperatures at
  any interval they like. It also manages a pubsub mechanism for updates.
  """

  use GenServer

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def init(opts) do
    opts |> IO.inspect()
    {:ok, opts}
  end
end
