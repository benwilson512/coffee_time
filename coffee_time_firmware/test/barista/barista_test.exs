defmodule CoffeeTimeFirmware.BaristaTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Barista
  alias CoffeeTimeFirmware.Measurement

  @moduletag :measurement_store

  setup %{context: context} do
    {:ok, _} = start_supervised({Barista.Super, %{context: context}})

    [{pid, _}] = Registry.lookup(context.registry, CoffeeTimeFirmware.Barista)

    {:ok, %{context: context, barista_pid: pid}}
  end

  test "initial state is sane", %{context: context} do
    assert {:idle, _} = :sys.get_state(name(context, Barista))
  end

  describe "boot process" do
    test "works", %{
      context: context
    } do
      Measurement.Store.put(context, :boiler_fill_status, :full)

      Barista.boot(context)

      assert {:ready, _} = :sys.get_state(name(context, Barista))
    end
  end

  describe "Program sanity checks" do
    setup [:spawn_subsystems, :boot]

    test "running a program that doesn't exist returns an error", %{context: context} do
      assert {:error, :not_found} = Barista.run_program(context, :does_not_exist)

      assert {:ready, _} = :sys.get_state(name(context, Barista))
    end

    test "can save and run a program", %{
      context: context
    } do
      PubSub.subscribe(context, :barista)
      Barista.save_program(context, %Barista.Program{name: :test})

      assert :ok = Barista.run_program(context, :test)

      assert {{:executing, _}, _} = :sys.get_state(name(context, Barista))

      assert_receive({:broadcast, :barista, {:program_start, %{name: :test}}})
    end
  end

  describe "Real Programs" do
    setup [:spawn_subsystems, :boot]

    @tag :capture_log
    test "when executing a program the barista process lives or dies with the hydraulics process",
         %{context: context, barista_pid: pid} do
      Process.monitor(pid)

      program = %Barista.Program{
        name: :espresso,
        grouphead_duration: :invalid_value
      }

      Barista.run_program(context, program)

      [{hydraulics_pid, _}] = Registry.lookup(context.registry, CoffeeTimeFirmware.Hydraulics)

      Process.exit(hydraulics_pid, :kill)

      assert_receive({:DOWN, _, :process, ^pid, _})
    end

    test "can start a simple program", %{context: context} do
      PubSub.subscribe(context, :grouphead_solenoid)
      PubSub.subscribe(context, :pump)

      program = %Barista.Program{
        name: :espresso,
        grouphead_duration: {:timer, 10}
      }

      assert :ok = Barista.run_program(context, program)

      assert_receive({:broadcast, :pump, :on})
      assert_receive({:broadcast, :grouphead_solenoid, :open})
    end

    test "trying to start a program while another is in progress fails", %{context: context} do
      program = %Barista.Program{
        name: :espresso,
        grouphead_duration: {:timer, :infinity}
      }

      assert :ok = Barista.run_program(context, program)
      assert {:error, :busy} = Barista.run_program(context, program)
    end
  end

  defp spawn_subsystems(%{context: context} = info) do
    start_supervised!({CoffeeTimeFirmware.Hydraulics, %{context: context}})
    info
  end

  defp boot(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    Barista.boot(context)
    assert {:ready, _} = :sys.get_state(name(context, Barista))
    info
  end
end
