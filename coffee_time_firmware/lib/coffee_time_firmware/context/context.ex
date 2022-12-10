defmodule CoffeeTimeFirmware.Context do
  @moduledoc """
  Defines the general execution context.

  This application uses this struct and passes it around in favor of having different processes
  directly query the application config. This dramatically simplifies testing.
  """
  defstruct [
    :registry,
    :pubsub,
    :hardware,
    :data_dir
  ]

  @type t() :: %__MODULE__{
          registry: atom(),
          pubsub: atom(),
          hardware: module()
        }

  # some of these functions should probably get moved to regular config.

  def new(:host) do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub,
      hardware: %CoffeeTimeFirmware.Hardware.Host{},
      data_dir: :code.priv_dir(:coffee_time_firmware)
    }
  end

  def new(:rpi3) do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub,
      hardware: %CoffeeTimeFirmware.Hardware.Pi{},
      data_dir: "/data"
    }
  end

  def get_pid(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    pid
  end

  def watchdog_config(_) do
    %{
      reboot_on_fault: true,
      deadline: %{
        pump: :timer.seconds(60),
        grouphead_solenoid: :timer.seconds(60),
        refill_solenoid: :timer.seconds(60)
      },
      healthcheck: %{
        cpu_temp: :timer.seconds(15),
        boiler_temp: :timer.seconds(5),
        boiler_fill_status: :timer.seconds(5)
      },
      threshold: %{
        cpu_temp: 70,
        boiler_temp: 130
      }
    }
  end
end
