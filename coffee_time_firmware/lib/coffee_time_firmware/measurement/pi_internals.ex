defmodule CoffeeTimeFirmware.Measurement.PiInternals do
  alias __MODULE__

  @moduledoc """
  Fetches the Pi CPU temp
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
