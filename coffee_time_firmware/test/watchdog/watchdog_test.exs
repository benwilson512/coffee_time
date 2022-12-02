defmodule CoffeeTimeFirmware.WatchdogTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  # import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Measurement
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

  @tag :measurement_store
  describe "fault conditions" do
    setup :setup_watchdog

    test "boiler overtemp faults", %{context: context} do
      Measurement.Store.put(context, :boiler_temp, 131)

      assert %CoffeeTimeFirmware.Watchdog.Fault{
               message: "boiler over temp: 131"
             } = Watchdog.get_fault(context)
    end
  end

  defp setup_watchdog(%{context: context}) do
    path = Briefly.create!()

    {:ok, _} =
      Watchdog.start_link(%{
        context: context,
        config: %{
          reboot_on_fault: false,
          fault_file_path: path
        }
      })

    {:ok, %{context: context, fault_file_path: path}}
  end
end
