defmodule CoffeeTime.BaristaTest do
  use CoffeeTime.ContextCase

  import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.PubSub
  alias CoffeeTime.Barista
  alias CoffeeTime.Measurement

  @moduletag :measurement_store
  @moduletag :watchdog

  setup %{context: context} do
    {:ok, _} = start_supervised({Barista, %{context: context}})

    [{pid, _}] = Registry.lookup(context.registry, CoffeeTime.Barista)

    {:ok, %{context: context, barista_pid: pid}}
  end

  describe "Program sanity checks" do
    setup [:spawn_subsystems]

    test "running a program that doesn't exist returns an error", %{context: context} do
      assert {:error, :not_found} = Barista.run_program(context, :does_not_exist)

      assert {:ready, _} = :sys.get_state(name(context, Barista))
    end

    test "can save and run a program", %{
      context: context
    } do
      PubSub.subscribe(context, :barista)

      :ok =
        Barista.save_program(context, %Barista.Program{
          name: :test,
          steps: [{:solenoid, :grouphead, :open}]
        })

      assert :ok = Barista.run_program(context, :test)

      assert_receive({:broadcast, :barista, {:program_start, %{name: :test}}})
      assert_receive({:broadcast, :barista, :ready})
    end

    test "halting a program terminates it early", %{context: context} do
      PubSub.subscribe(context, :barista)

      :ok =
        Barista.save_program(context, %Barista.Program{
          name: :test,
          steps: [
            {:solenoid, :grouphead, :open},
            {:wait, :timer, :infinity},
            {:hydraulics, :halt}
          ]
        })

      assert :ok = Barista.run_program(context, :test)
      assert :ok = Barista.halt(context)

      assert_receive({:broadcast, :barista, {:program_start, %{name: :test}}})
      assert_receive({:broadcast, :barista, :ready})
    end
  end

  describe "Real Programs" do
    setup [:spawn_subsystems]

    @tag :capture_log
    test "when executing a program the barista process lives or dies with the hydraulics process",
         %{context: context, barista_pid: pid} do
      Process.monitor(pid)

      program = %Barista.Program{
        name: :espresso,
        steps: [
          {:wait, :timer, :infinity},
          {:hydraulics, :halt}
        ]
      }

      :ok = Barista.run_program(context, program)
      {{:executing, _}, _} = :sys.get_state(name(context, Barista))

      [{hydraulics_pid, _}] = Registry.lookup(context.registry, CoffeeTime.Hydraulics)

      Process.exit(hydraulics_pid, :kill)

      assert_receive({:DOWN, _, :process, ^pid, _})
    end

    test "can start a simple program", %{context: context} do
      PubSub.subscribe(context, :grouphead_solenoid)
      PubSub.subscribe(context, :pump)

      program = %Barista.Program{
        name: :espresso,
        steps: [
          {:solenoid, :grouphead, :open},
          {:pump, :on},
          {:hydraulics, :halt}
        ]
      }

      assert :ok = Barista.run_program(context, program)

      assert_receive({:broadcast, :pump, :on})
      assert_receive({:broadcast, :grouphead_solenoid, :open})
      assert_receive({:broadcast, :pump, :off})
      assert_receive({:broadcast, :grouphead_solenoid, :close})
    end

    test "wait works correctly", %{context: context} do
      PubSub.subscribe(context, :grouphead_solenoid)
      PubSub.subscribe(context, :pump)

      program = %Barista.Program{
        name: :espresso,
        steps: [
          {:solenoid, :grouphead, :open},
          {:pump, :on},
          {:wait, :timer, 50},
          {:hydraulics, :halt}
        ]
      }

      assert :ok = Barista.run_program(context, program)

      assert_receive({:broadcast, :pump, :on})
      assert_receive({:broadcast, :grouphead_solenoid, :open})
      refute_receive({:broadcast, :pump, :off}, 0)
      refute_receive({:broadcast, :grouphead_solenoid, :close}, 0)

      Process.sleep(50)
      assert_receive({:broadcast, :pump, :off})
      assert_receive({:broadcast, :grouphead_solenoid, :close})
    end

    test "trying to start a program while another is in progress fails", %{context: context} do
      program = %Barista.Program{
        name: :espresso,
        steps: [
          {:wait, :timer, :infinity},
          {:solenoid, :grouphead, :on}
        ]
      }

      assert :ok = Barista.run_program(context, program)
      assert {:error, :busy} = Barista.run_program(context, program)
    end
  end

  defp spawn_subsystems(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    start_supervised!({CoffeeTime.Hydraulics, %{context: context}}, restart: :permanent)

    start_supervised!(
      {CoffeeTime.Boiler,
       %{
         context: context,
         intervals: %{
           CoffeeTime.Boiler.DutyCycle => %{write_interval: :infinity}
         }
       }}
    )

    info
  end
end
