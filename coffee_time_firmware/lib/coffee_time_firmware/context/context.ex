defmodule CoffeeTimeFirmware.Context do
  defstruct [
    :registry,
    :pubsub,
    :layout
  ]

  def breaker_config() do
    %{
      shutdown_override_gpio: 13,
      fault_deadlines: %{
        boiler_temp_update: :timer.seconds(10)
      }
    }
  end
end
