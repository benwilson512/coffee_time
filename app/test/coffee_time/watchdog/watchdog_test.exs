defmodule CoffeeTime.WatchdogTest do
  use CoffeeTime.ContextCase

  # import CoffeeTime.Application, only: [name: 2]

  alias CoffeeTime.PubSub
  alias CoffeeTime.Watchdog

  @moduletag capture_log: true

  describe "init/1" do
    test "no fault file means no fault", %{context: context} do
      assert {:ok, _} =
               Watchdog.start_link(%{
                 context: context,
                 config: %{
                   reboot_on_fault: false
                 }
               })

      assert nil == Watchdog.get_fault(context)
    end

    test "fault file means initial fault", %{context: context} do
      fault_info = %{message: "test fault", occurred_at: ~U[2022-01-01T00:00:00Z]}
      File.write(Watchdog.fault_file_path(context), Jason.encode!(fault_info))

      assert {:ok, _} =
               Watchdog.start_link(%{
                 context: context,
                 config: %{
                   reboot_on_fault: false
                 }
               })

      assert %CoffeeTime.Watchdog.Fault{
               message: "test fault",
               occurred_at: ~U[2022-01-01 00:00:00Z]
             } == Watchdog.get_fault(context)
    end
  end

  describe "thresholds" do
    setup :setup_watchdog

    @tag bound: %{boiler_pressure: 7000..14000}
    test "boiler high pressure faults", %{context: context} do
      # send 4 bad values so that we exceed the grace period
      for _ <- 1..4 do
        PubSub.broadcast(context, :boiler_pressure, 14_500)
      end

      assert_receive({:DOWN, _, :process, _, :fault}, 100)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message:
                 "Boundary violated: The value of boiler_pressure, 14500, violates 7000..14000"
             } = Watchdog.get_fault(context)
    end

    @tag :boiler_temp
    @tag bound: %{boiler_temp: 0..130}
    test "boiler high temp faults", %{context: context} do
      # send 4 bad values so that we exceed the grace period
      for _ <- 1..4 do
        PubSub.broadcast(context, :boiler_temp, 131)
      end

      assert_receive({:DOWN, _, :process, _, :fault}, 100)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Boundary violated: The value of boiler_temp, 131, violates 0..130"
             } = Watchdog.get_fault(context)
    end

    @tag bound: %{cpu_temp: 0..50}
    test "cpu high temp faults", %{context: context} do
      for _ <- 1..4 do
        PubSub.broadcast(context, :cpu_temp, 51)
      end

      assert_receive({:DOWN, _, :process, _, :fault}, 100)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Boundary violated: The value of cpu_temp, 51, violates 0..50"
             } = Watchdog.get_fault(context)
    end
  end

  describe "healthchecks" do
    setup :setup_watchdog

    @tag healthcheck: %{boiler_pressure: 10}
    test "boiler pressure faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Healthcheck failed timeout: :boiler_pressure"
             } = Watchdog.get_fault(context)
    end

    @tag healthcheck: %{boiler_pressure: 50}
    test "boiler pressure ping makes it happy", %{context: context} do
      Process.sleep(40)
      PubSub.broadcast(context, :boiler_pressure, 10000)
      Process.sleep(40)
      # Even though we've slept for 16 total milliseconds which exceesd the 10ms limit,
      # we should still be OK because we got a ping in the middle which resets the timer
      assert nil == Watchdog.get_fault(context)
    end

    @tag :boiler_temp
    @tag healthcheck: %{boiler_temp: 10}
    test "boiler temp delay faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Healthcheck failed timeout: :boiler_temp"
             } = Watchdog.get_fault(context)
    end

    @tag healthcheck: %{boiler_temp: 50}

    @tag :boiler_temp
    test "boiler temp ping makes it happy", %{context: context} do
      Process.sleep(40)
      PubSub.broadcast(context, :boiler_temp, 120)
      Process.sleep(40)
      # Even though we've slept for 16 total milliseconds which exceesd the 10ms limit,
      # we should still be OK because we got a ping in the middle which resets the timer
      assert nil == Watchdog.get_fault(context)
    end

    @tag healthcheck: %{cpu_temp: 10}
    test "cpu temp delay faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 100)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Healthcheck failed timeout: :cpu_temp"
             } = Watchdog.get_fault(context)
    end

    @tag healthcheck: %{cpu_temp: 50}

    test "cpu_temp ping makes it happy", %{context: context} do
      Process.sleep(40)
      PubSub.broadcast(context, :cpu_temp, 50)
      Process.sleep(40)
      # Even though we've slept for 16 total milliseconds which exceesd the 10ms limit,
      # we should still be OK because we got a ping in the middle which resets the timer
      assert nil == Watchdog.get_fault(context)
    end

    @tag healthcheck: %{boiler_fill_status: 10}
    test "boiler_fill_status delay faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Healthcheck failed timeout: :boiler_fill_status"
             } = Watchdog.get_fault(context)
    end

    @tag healthcheck: %{boiler_fill_status: 10}

    test "boiler_fill_status ping makes it happy", %{context: context} do
      Process.sleep(8)
      PubSub.broadcast(context, :boiler_fill_status, 50)
      Process.sleep(8)
      # Even though we've slept for 16 total milliseconds which exceesd the 10ms limit,
      # we should still be OK because we got a ping in the middle which resets the timer
      assert nil == Watchdog.get_fault(context)
    end
  end

  describe "deadlines" do
    setup :setup_watchdog

    @tag deadline: %{pump: 10}
    test "pump on too long faults", %{context: context} do
      PubSub.broadcast(context, :pump, :on)

      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Deadline failed timeout: :pump"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{refill_solenoid: 10}
    test "refill solenoid on long faults", %{context: context} do
      PubSub.broadcast(context, :refill_solenoid, :open)

      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 100)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Deadline failed timeout: :refill_solenoid"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{grouphead_solenoid: 10}
    test "grouphead solenoid on long faults", %{context: context} do
      PubSub.broadcast(context, :grouphead_solenoid, :open)

      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTime.Watchdog.Fault{
               message: "Deadline failed timeout: :grouphead_solenoid"
             } = Watchdog.get_fault(context)
    end
  end

  describe "allowances" do
    setup [:setup_watchdog]

    @tag deadline: %{grouphead_solenoid: 1}
    test "an allowance can be acquired and then released", %{
      context: context,
      watchdog_pid: watchdog_pid
    } do
      assert :ok = Watchdog.acquire_allowance(context, :deadline, :grouphead_solenoid, :infinity)
      assert :sys.get_state(watchdog_pid).deadline.grouphead_solenoid == :infinity
      assert :sys.get_state(watchdog_pid).allowances[{:deadline, :grouphead_solenoid}]
      assert :ok = Watchdog.release_allowance(context, :deadline, :grouphead_solenoid)
      assert :sys.get_state(watchdog_pid).deadline.grouphead_solenoid == 1
      assert :sys.get_state(watchdog_pid).allowances == %{}
    end

    @tag deadline: %{grouphead_solenoid: 1}
    test "an allowance cannot be acquired multiple times", %{context: context} do
      self = self()
      assert :ok = Watchdog.acquire_allowance(context, :deadline, :grouphead_solenoid, :infinity)

      assert {:error, {:already_taken, ^self}} =
               Watchdog.acquire_allowance(context, :deadline, :grouphead_solenoid, :infinity)
    end

    @tag deadline: %{grouphead_solenoid: 1}
    test "allowances are released when the owner pid dies", %{
      context: context,
      watchdog_pid: watchdog_pid
    } do
      owner_pid = spawn(fn -> Process.sleep(:infinity) end)

      assert :ok =
               Watchdog.acquire_allowance(context, :deadline, :grouphead_solenoid, :infinity,
                 owner: owner_pid
               )

      Process.exit(owner_pid, :kill)
      refute Process.alive?(owner_pid)

      assert :sys.get_state(watchdog_pid).deadline.grouphead_solenoid == 1
      assert :sys.get_state(watchdog_pid).allowances == %{}
    end
  end

  defp setup_watchdog(%{context: context} = params) do
    pid =
      start_supervised!(
        {Watchdog,
         %{
           context: context,
           config: %{
             reboot_on_fault: false,
             healthcheck: params[:healthcheck] || %{},
             deadline: params[:deadline] || %{},
             bound: params[:bound] || %{}
           }
         }}
      )

    Process.monitor(pid)

    {:ok, %{watchdog_pid: pid, context: context}}
  end
end
