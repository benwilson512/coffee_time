defmodule CoffeeTimeFirmwareTest do
  use ExUnit.Case
  doctest CoffeeTimeFirmware

  test "greets the world" do
    assert CoffeeTimeFirmware.hello() == :world
  end
end
