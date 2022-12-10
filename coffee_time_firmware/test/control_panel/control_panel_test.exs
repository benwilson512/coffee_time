defmodule CoffeeTimeFirmware.ControlPanelTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.PubSub
  alias CoffeeTimeFirmware.Watchdog
  alias CoffeeTimeFirmware.ControlPanel
  alias CoffeeTimeFirmware.Barista

  @moduletag :measurement_store
  @moduletag :watchdog

  describe "boot process" do
    @tag :capture_log
    test "If there is a fault we go to the fault state", %{
      context: context
    } do
      PubSub.subscribe(context, :watchdog)

      Watchdog.fault!(context, "test")

      assert_receive({:broadcast, :watchdog, :fault_state})

      {:ok, pid} =
        ControlPanel.start_link(%{
          context: context,
          config: %{fault_blink_rate: :infinity}
        })

      assert {{:fault, _}, _} = :sys.get_state(name(context, ControlPanel))

      # Blinky
      assert_receive({:write_gpio, :led1, 1})
      assert_receive({:write_gpio, :led2, 1})
      assert_receive({:write_gpio, :led3, 1})
      assert_receive({:write_gpio, :led4, 1})

      send(pid, :blink)
      assert_receive({:write_gpio, :led1, 0})
      assert_receive({:write_gpio, :led2, 0})
      assert_receive({:write_gpio, :led3, 0})
      assert_receive({:write_gpio, :led4, 0})

      send(pid, :blink)
      assert_receive({:write_gpio, :led1, 1})
      assert_receive({:write_gpio, :led2, 1})
      assert_receive({:write_gpio, :led3, 1})
      assert_receive({:write_gpio, :led4, 1})
    end

    test "if there is no fault we are ready to go", %{context: context} do
      {:ok, _} =
        ControlPanel.start_link(%{
          context: context,
          config: %{fault_blink_rate: :infinity}
        })

      assert {:ready, _} = :sys.get_state(name(context, ControlPanel))
    end
  end

  describe "button presses" do
    setup [:boot]
  end

  describe "barista notifications" do
    setup [:boot, :boot_barista]

    test "message from barista displays the right LED", %{context: context} do
      :ok =
        Barista.run_program(context, %Barista.Program{name: :foo, steps: [{:hydraulics, :halt}]})

      # things shouldn't blow up.
      Process.sleep(100)
    end
  end

  defp boot(%{context: context}) do
    {:ok, _} =
      ControlPanel.start_link(%{
        context: context,
        config: %{fault_blink_rate: :infinity}
      })

    :ok
  end

  defp boot_barista(%{context: context}) do
    start_supervised!({Barista, %{context: context}})

    :ok
  end
end
