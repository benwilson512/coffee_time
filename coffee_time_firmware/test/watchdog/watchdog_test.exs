defmodule CoffeeTimeFirmware.WatchdogTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  # import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Watchdog

  @moduletag capture_log: true

  describe "init/1" do
    test "no fault file means no fault", %{context: context} do
      assert {:ok, _} =
               Watchdog.start_link(%{
                 context: context,
                 config: %{
                   reboot_on_fault: false,
                   fault_file_path: Briefly.create!()
                 }
               })

      assert nil == Watchdog.get_fault(context)
    end

    test "fault file means initial fault", %{context: context} do
      path = Briefly.create!()

      fault_info = %{message: "test fault", occurred_at: ~U[2022-01-01T00:00:00Z]}
      File.write(path, Jason.encode!(fault_info))

      assert {:ok, _} =
               Watchdog.start_link(%{
                 context: context,
                 config: %{
                   reboot_on_fault: false,
                   fault_file_path: path
                 }
               })

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "test fault",
               occurred_at: ~U[2022-01-01 00:00:00Z]
             } == Watchdog.get_fault(context)
    end
  end

  describe "thresholds" do
    setup :setup_watchdog

    @tag threshold: %{boiler_temp: 130}
    test "boiler high temp faults", %{context: context} do
      PubSub.broadcast(context, :boiler_temp, 131)
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault})
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Threshold exceeded: The value of boiler_temp, 131, exceeds 130"
             } = Watchdog.get_fault(context)
    end

    @tag threshold: %{cpu_temp: 50}
    test "cpu high temp faults", %{context: context} do
      PubSub.broadcast(context, :cpu_temp, 51)
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault})
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Threshold exceeded: The value of cpu_temp, 51, exceeds 50"
             } = Watchdog.get_fault(context)
    end
  end

  describe "healthchecks" do
    setup :setup_watchdog

    @tag healthcheck: %{boiler_temp: 10}
    test "boiler delay faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Healthcheck failed timeout: :boiler_temp"
             } = Watchdog.get_fault(context)
    end

    @tag healthcheck: %{boiler_temp: 10}

    test "boiler temp ping makes it happy", %{context: context} do
      Process.sleep(8)
      PubSub.broadcast(context, :boiler_temp, 120)
      Process.sleep(8)
      # Even though we've slept for 16 total milliseconds which exceesd the 10ms limit,
      # we should still be OK because we got a ping in the middle which resets the timer
      assert nil == Watchdog.get_fault(context)
    end

    @tag healthcheck: %{cpu_temp: 10}
    test "cpu temp delay faults", %{context: context} do
      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
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

      assert %CoffeeTimeFirmware.Watchdog.Fault{
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

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Deadline failed timeout: :pump"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{refill_solenoid: 10}
    test "refill solenoid on long faults", %{context: context} do
      PubSub.broadcast(context, :refill_solenoid, :open)

      # If we wait up to 50ms we exceed the deadline of 10ms so it should crash.
      assert_receive({:DOWN, _, :process, _, :fault}, 50)
      # Give the supervisor time to reboot it.
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
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

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Deadline failed timeout: :grouphead_solenoid"
             } = Watchdog.get_fault(context)
    end
  end

  defp setup_watchdog(%{context: context} = params) do
    path = Briefly.create!()

    pid =
      start_supervised!(
        {Watchdog,
         %{
           context: context,
           config: %{
             reboot_on_fault: false,
             fault_file_path: path,
             healthcheck: params[:healthcheck] || %{},
             deadline: params[:deadline] || %{},
             threshold: params[:threshold] || %{}
           }
         }}
      )

    Process.monitor(pid)

    {:ok, %{watchdog_pid: pid, context: context, fault_file_path: path}}
  end
end
