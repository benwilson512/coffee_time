defmodule CoffeeTime.Context do
  @moduledoc """
  Defines the general execution context.

  This application uses this struct and passes it around in favor of having different processes
  directly query the application config. This dramatically simplifies testing.
  """
  defstruct [
    :registry,
    :pubsub,
    :hardware,
    :data_dir,
    root: false
  ]

  @type t() :: %__MODULE__{
          registry: atom(),
          pubsub: atom(),
          hardware: any()
        }

  # some of these functions should probably get moved to regular config.

  def new(:host) do
    %CoffeeTime.Context{
      registry: CoffeeTime.Registry,
      pubsub: CoffeeTime.PubSub,
      hardware: %CoffeeTime.Hardware.Host{},
      data_dir: :code.priv_dir(:coffee_time),
      root: true
    }
  end

  def new(:rpi3) do
    %CoffeeTime.Context{
      registry: CoffeeTime.Registry,
      pubsub: CoffeeTime.PubSub,
      hardware: %CoffeeTime.Hardware.Pi{},
      data_dir: "/data",
      root: true
    }
  end

  def get_pid(context, name) do
    GenServer.whereis(CoffeeTime.Application.name(context, name))
  end

  def watchdog_config(:rpi3) do
    %{
      reboot_on_fault: true,
      deadline: %{
        pump: :timer.seconds(60),
        grouphead_solenoid: :timer.seconds(60),
        # In normal operation the refill solenoid should only be on very briefly. Currently one of my
        # biggest concerns is that some part of the boiler refill circuit fails and it tries to fill for
        # too long. Most of the other hardware failures failing closed isn't all that much of a problem but
        # the pump pushing 120C water out of the boiler OPV would be super dangerous.
        #
        # TODO: This does leave out the scenario where the boiler needs to be refilled on boot. Specific
        # logic should be written to adjust the deadline in that case.
        refill_solenoid: :timer.seconds(5)
      },
      healthcheck: %{
        cpu_temp: :timer.seconds(15),
        # boiler_temp: :timer.seconds(5),
        boiler_pressure: :timer.seconds(5),
        boiler_fill_status: :timer.seconds(10)
      },
      bound: %{
        cpu_temp: 10..70,
        # boiler_temp: 10..130,
        boiler_pressure: 5_000..14_500
      }
    }
  end

  def watchdog_config(_) do
    %{}
  end
end
