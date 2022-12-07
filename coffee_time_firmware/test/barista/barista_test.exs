defmodule CoffeeTimeFirmware.BaristaTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Barista
  alias CoffeeTimeFirmware.Measurement

  @moduletag :measurement_store

  setup %{context: context} do
    {:ok, _} = start_supervised({Barista.Super, %{context: context}})

    {:ok, %{context: context}}
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

  describe "basic preset logic" do
    setup :boot

    test "running a preset that doesn't exist returns an error", %{context: context} do
      assert {:error, :preset_not_found} = Barista.run_preset(context, :does_not_exist)

      assert {:ready, _} = :sys.get_state(name(context, Barista))
    end

    test "can set and run a preset", %{
      context: context
    } do
      Barista.put_preset(context, :test, %Barista.Preset{})

      assert :ok = Barista.run_preset(context, :test)

      assert {{:running_preset, _}, _} = :sys.get_state(name(context, Barista))
    end
  end

  defp boot(%{context: context} = info) do
    Measurement.Store.put(context, :boiler_fill_status, :full)
    Barista.boot(context)
    assert {:ready, _} = :sys.get_state(name(context, Barista))
    info
  end
end
