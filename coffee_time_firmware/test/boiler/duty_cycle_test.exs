defmodule CoffeeTimeFirmware.Boiler.DutyCycleTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  # import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Boiler

  test "exiting the process resets gpio to 0", %{context: context} do
    {:ok, _} =
      start_supervised(
        {Boiler.DutyCycle,
         %{
           context: context,
           intervals: %{
             # The point of the infinite value here is that we never really want the timer to go off,
             # we are always going to trigger it manually for these tests
             Boiler.DutyCycle => %{write_interval: :infinity}
           }
         }},
        restart: :temporary
      )

    Boiler.DutyCycle.set(context, 10)
    assert_receive({:write_gpio, :duty_cycle, 1})

    stop_supervised(Boiler.DutyCycle)
    assert_receive({:write_gpio, :duty_cycle, 0})
  end

  describe "basic sanity checks" do
    setup :setup_process

    test "a duty cycle of 0 writes all 0s to gpio", %{pid: pid} do
      assert %{duty_cycle: 0, subdivisions: subdivisions} = :sys.get_state(pid)

      for _i <- 0..(subdivisions + 1) do
        send(pid, :tick)
        assert_receive({:write_gpio, :duty_cycle, 0})
      end
    end

    test "a duty cycle of 10 writes all 1s to gpio", %{context: context, pid: pid} do
      Boiler.DutyCycle.set(context, 10)
      assert %{duty_cycle: 10, subdivisions: subdivisions} = :sys.get_state(pid)

      for _i <- 0..(subdivisions + 1) do
        send(pid, :tick)
        assert_receive({:write_gpio, :duty_cycle, 1})
      end
    end
  end

  describe "fancy logic" do
    setup :setup_process

    test "50% is even", %{context: context, pid: pid} do
      Boiler.DutyCycle.set(context, 5)

      values =
        for _i <- 1..10 do
          send(pid, :tick)
          assert_receive({:write_gpio, :duty_cycle, val})
          val
        end

      assert values == [1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
    end

    for duty_cycle <- 0..10 do
      percentage = duty_cycle * 10

      @tag duty_cycle: duty_cycle
      test "#{percentage}% works correctly", %{context: context, pid: pid, duty_cycle: duty_cycle} do
        Boiler.DutyCycle.set(context, duty_cycle)

        results =
          for _i <- 1..10 do
            send(pid, :tick)
            assert_receive({:write_gpio, :duty_cycle, val})
            val
          end

        expected = List.duplicate(1, duty_cycle) ++ List.duplicate(0, 10 - duty_cycle)

        assert expected == results
      end
    end
  end

  def setup_process(%{context: context}) do
    {:ok, pid} =
      start_supervised({
        CoffeeTimeFirmware.Boiler.DutyCycle,
        %{
          context: context,
          intervals: %{
            # The point of the infinite value here is that we never really want the timer to go off,
            # we are always going to trigger it manually for these tests
            Boiler.DutyCycle => %{write_interval: :infinity}
          }
        }
      })

    {:ok, %{context: context, pid: pid}}
  end
end
