defmodule CoffeeTimeFirmware.Context do
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

  # some of these functions should probably get moved to regular config.

  def new(:host) do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub,
      hardware: %CoffeeTimeFirmware.Hardware.Host{}
    }
  end

  def new(:rpi3) do
    %CoffeeTimeFirmware.Context{
      registry: CoffeeTimeFirmware.Registry,
      pubsub: CoffeeTimeFirmware.PubSub,
      hardware: %CoffeeTimeFirmware.Hardware.Pi{}
    }
  end

  def get_pid(context, name) do
    [{pid, _}] = Registry.lookup(context.registry, name)
    pid
  end

  def watchdog_config(:rpi3) do
    %{
      fault_file_path: "/data/fault.json",
      reboot_on_fault: true,
      deadline: %{
        pump: :timer.seconds(60),
        grouphead_solenoid: :timer.seconds(60),
        refill_solenoid: :timer.seconds(60)
      },
      healthcheck: %{
        cpu_temp: :timer.seconds(10),
        boiler_temp: :timer.seconds(5),
        boiler_fill_status: :timer.seconds(5)
      },
      threshold: %{
        cpu_temp: 50,
        boiler_temp: 130
      }
    }
  end

  def watchdog_config(:host) do
    path =
      :code.priv_dir(:coffee_time_firmware)
      |> Path.join("fault.json")

    watchdog_config(:rpi3)
    |> Map.replace!(:fault_file_path, path)
  end
end
