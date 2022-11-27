defmodule Help do
  defmacro __using__(_) do
    quote do
      import CoffeeTimeFirmware.Application, only: [name: 2]
      import unquote(__MODULE__)
      alias CoffeeTimeFirmware.PubSub
    end
  end

  def context() do
    CoffeeTimeFirmware.Context.new(:rpi3)
  end
end
