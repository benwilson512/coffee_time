defmodule CoffeeTimeFirmware.Context do
  alias Max31865.Registers

  defstruct [
    :registry,
    :pubsub,
    :hardware
  ]

  @type t() :: %__MODULE__{
          registry: atom(),
          pubsub: atom(),
          hardware: module()
        }

  def new(:host) do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub,
      hardware: %CoffeeTimeFirmware.Hardware.Host{}
    }
  end

  def get_pid(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    pid
  end

  def breaker_config() do
    %{
      shutdown_override_gpio: 13,
      fault_deadlines: %{
        boiler_temp_update: :timer.seconds(10)
      }
    }
  end
end
