defmodule CoffeeTimeFirmware.Breakers do
  use GenServer

  @moduledoc """
  Identifies and logs faults, shutting down the pi if any are found.
  """

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def init(opts) do
    opts |> IO.inspect()
    {:ok, opts}
  end
end
