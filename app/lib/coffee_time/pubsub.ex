defmodule CoffeeTime.PubSub do
  def subscribe(context, key, opts \\ []) do
    {:ok, _} = Registry.register(context.pubsub, key, opts)
  end

  def unsubscribe(context, key) do
    Registry.unregister(context.pubsub, key)
  end

  def broadcast(%{pubsub: pubsub}, key, value) do
    Registry.dispatch(pubsub, key, &do_broadcast(&1, key, value), parallel: false)
    Registry.dispatch(pubsub, "*", &do_broadcast(&1, key, value), parallel: false)
  end

  def ls(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  defp do_broadcast(entries, key, value) do
    for {pid, opts} <- entries do
      if fun = opts[:on_broadcast] do
        fun.(pid, key, value)
      else
        send(pid, {:broadcast, key, value})
      end
    end
  end
end
