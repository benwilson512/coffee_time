defmodule CoffeeTimeFirmware.Boiler.Control do
  use GenServer

  @moduledoc """
  Handles the PID loop for the boiler
  """

  defstruct []

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def init(opts) do
    opts |> IO.inspect()
    {:ok, opts}
  end

  def handle_continue(:duty_cycle, state) do
  end
end
