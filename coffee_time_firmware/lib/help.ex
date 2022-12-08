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

  @programs [
    %CoffeeTimeFirmware.Barista.Program{
      name: :short_flush
    },
    %CoffeeTimeFirmware.Barista.Program{
      name: :long_flush
    },
    %CoffeeTimeFirmware.Barista.Program{
      name: :standard_espresso
    }
  ]
  def __reseed__() do
    context = context()
    Enum.each(@programs, &CoffeeTimeFirmware.Barista.save_program(context, &1))
  end

  def __restart__() do
    Application.stop(:coffee_time_firmware)
    Application.start(:coffee_time_firmware)
  end
end
