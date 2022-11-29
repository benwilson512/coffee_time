defmodule CoffeeTimeFirmware.Measurement.StoreTest do
  use CoffeeTimeFirmware.ContextCase, async: true

  # import CoffeeTimeFirmware.Application, only: [name: 2]

  alias CoffeeTimeFirmware.Measurement

  setup %{context: context} do
    {:ok, _} =
      Measurement.Store.start_link(%{
        context: context
      })

    {:ok, %{context: context}}
  end

  test "Values can be set and looked up", %{context: context} do
    Measurement.Store.put(context, :boiler_temp, 1)
    assert %{boiler_temp: 1} == Measurement.Store.take(context, [:boiler_temp])
    assert 1 == Measurement.Store.fetch!(context, :boiler_temp)
  end

  test "pubsub works", %{context: context} do
    Measurement.Store.subscribe(context, :boiler_temp)

    Measurement.Store.put(context, :boiler_temp, 1)
    assert_receive({:broadcast, :boiler_temp, 1})
  end
end
