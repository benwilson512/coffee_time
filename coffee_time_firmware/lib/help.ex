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
      name: :short_flush,
      steps: [
        {:solenoid, :grouphead, :open},
        {:pump, :on},
        {:wait, :timer, 2000},
        {:hydraulics, :halt}
      ]
    },
    %CoffeeTimeFirmware.Barista.Program{
      name: :long_flush,
      steps: [
        {:solenoid, :grouphead, :open},
        {:pump, :on},
        {:wait, :timer, 10000},
        {:hydraulics, :halt}
      ]
    },
    %CoffeeTimeFirmware.Barista.Program{
      name: :double_espresso,
      steps: [
        {:solenoid, :grouphead, :open},
        {:wait, :timer, 4000},
        {:pump, :on},
        {:wait, :timer, 50000},
        {:hydraulics, :halt}
      ]
    }
  ]
  def __reseed__() do
    context = context()
    [{db, _}] = Registry.lookup(context.registry, :db)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    CubDB.back_up(db, Path.join([context.data_dir, "coffee_time_db-#{now}"]))

    Enum.each(@programs, &CoffeeTimeFirmware.Barista.save_program(context, &1))
    CubDB.put(db, {:control_panel, :button1}, {:program, :short_flush})
    CubDB.put(db, {:control_panel, :button2}, {:program, :double_espresso})
    CubDB.put(db, {:control_panel, :button4}, {:program, :long_flush})
  end

  def __restart__() do
    Application.stop(:coffee_time_firmware)
    Application.start(:coffee_time_firmware)
  end
end
