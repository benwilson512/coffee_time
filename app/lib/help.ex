defmodule Help do
  defmacro __using__(_) do
    quote do
      import CoffeeTime.Application, only: [name: 2]
      import unquote(__MODULE__)
      alias CoffeeTime.PubSub
    end
  end

  def context() do
    CoffeeTime.Context.new(:rpi3)
  end

  def set_maintenance_mode(arg) do
    CoffeeTime.Boiler.DutyCycle.set_maintenance_mode(context(), arg)
  end

  @programs [
    %CoffeeTime.Barista.Program{
      name: :short_flush,
      steps: [
        {:solenoid, :grouphead, :open},
        {:pump, :on},
        {:wait, :timer, 2000},
        {:hydraulics, :halt}
      ]
    },
    %CoffeeTime.Barista.Program{
      name: :long_flush,
      steps: [
        {:solenoid, :grouphead, :open},
        {:pump, :on},
        {:wait, :timer, 10000},
        {:hydraulics, :halt}
      ]
    },
    %CoffeeTime.Barista.Program{
      name: :double_espresso,
      steps: [
        {:solenoid, :grouphead, :open},
        {:wait, :flow_pulse, 60},
        {:pump, :on},
        {:wait, :flow_pulse, 101},
        {:hydraulics, :halt}
      ]
    }
  ]
  def __reseed__() do
    context = context()
    db = CoffeeTime.Application.db(context)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    CubDB.back_up(db, Path.join([context.data_dir, "coffee_time_db-#{now}"]))

    Enum.each(@programs, &CoffeeTime.Barista.save_program(context, &1))
    CubDB.put(db, {:control_panel, :button1}, {:program, :short_flush})
    CubDB.put(db, {:control_panel, :button2}, {:program, :double_espresso})
    CubDB.put(db, {:control_panel, :button4}, {:program, :long_flush})
  end

  def __restart__() do
    Application.stop(:coffee_time)
    Application.start(:coffee_time)
  end
end
