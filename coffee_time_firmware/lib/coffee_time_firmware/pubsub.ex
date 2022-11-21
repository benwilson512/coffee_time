defmodule CoffeeTimeFirmware.PubSub do
  def subscribe(context, key) do
    {:ok, _} = Registry.register(context.pubsub, key, [])
  end

  def unsubscribe(context, key) do
    Registry.unregister(context.pubsub, key)
  end

  def broadcast(context, key, value) do
    Registry.dispatch(context.pubsub, key, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, key, value})
    end)

    Registry.dispatch(context.pubsub, "*", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, key, value})
    end)
  end

  def ls(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end
end
