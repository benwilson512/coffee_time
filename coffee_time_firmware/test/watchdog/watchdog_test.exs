defmodule CoffeeTimeFirmware.WatchdogTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  # import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Watchdog

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

  @moduletag capture_log: true
  describe "basic fault condition tests" do
    setup :setup_watchdog

    @tag healthcheck: %{boiler_temp: 10}
    test "boiler overtemp faults", %{watchdog_pid: pid, context: context} do
      PubSub.broadcast(context, :boiler_temp, 131)

      assert_receive({:DOWN, _, :process, ^pid, :fault})
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "boiler over temp: 131"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{pump: 10}
    test "pump on too long faults", %{context: context} do
      PubSub.broadcast(context, :pump, :on)

      assert_receive({:DOWN, _, :process, _, :fault})
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Deadline failed timeout: :pump"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{refill_solenoid: 10}
    test "refill solenoid on long faults", %{context: context} do
      PubSub.broadcast(context, :refill_solenoid, :open)

      assert_receive({:DOWN, _, :process, _, :fault})
      Process.sleep(50)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "Deadline failed timeout: :refill_solenoid"
             } = Watchdog.get_fault(context)
    end

    @tag deadline: %{grouphead_solenoid: 10}
    test "grouphead solenoid on long faults", %{context: context} do
      PubSub.broadcast(context, :grouphead_solenoid, :open)

      assert_receive({:DOWN, _, :process, _, :fault})
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
             threshold: %{
               cpu_temp: 50,
               boiler_temp: 130
             }
           }
         }}
      )

    Process.monitor(pid)

    {:ok, %{watchdog_pid: pid, context: context, fault_file_path: path}}
  end
end
