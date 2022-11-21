defmodule Help do
  defmacro __using__(_) do
    quote do
      import CoffeeTimeFirmware.Application, only: [context: 0, name: 2]
      alias CoffeeTimeFirmware.PubSub
    end
  end
end
