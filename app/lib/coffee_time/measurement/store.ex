defmodule CoffeeTime.Measurement.Store do
  @moduledoc """
  Handles storing measured values.

  Direct access to the sensors generally needs to be mediated by specific processes that are controlling
  GPIO state and other hardware internals.

  This process centralizes all recorded values to allow interested parties to access known temperatures at
  any interval they like. It also manages a pubsub mechanism for updates.
  """

  alias CoffeeTime.PubSub
  alias CoffeeTime.Context

  use GenServer

  defstruct [
    :context,
    :ets
  ]

  @type known_measurement() :: :boiler_temp | :boiler_fill_status | :cpu_temp | :ssr_temp

  @spec put(CoffeeTime.Context.t(), known_measurement, term) :: :ok
  def put(context, key, value) do
    [{_, ets}] = Registry.lookup(context.registry, :measurement_ets)

    :ets.insert(ets, {key, value})
    PubSub.broadcast(context, key, value)

    :ok
  end

  @doc """
  Mostly just a pass through to PubSub.subscribe/2 but it gives us a bit more flexibility to change
  the message shape later, and it gives us a typespec which will help enforce correctness
  """
  # @spec subscribe(CoffeeTime.Context.t(), known_measurement()) :: :ok
  def subscribe(%Context{} = context, key, opts \\ []) do
    PubSub.subscribe(context, key, opts)
    :ok
  end

  @spec fetch!(CoffeeTime.Context.t(), known_measurement()) :: term
  def fetch!(context, key) do
    case take(context, [key]) do
      %{^key => value} ->
        value

      _ ->
        raise KeyError,
              "#{inspect(key)} not found in measurement store of registry #{inspect(context.registry)}"
    end
  end

  def get(context, key) do
    case take(context, [key]) do
      %{^key => value} ->
        value

      _ ->
        nil
    end
  end

  @spec take(CoffeeTime.Context.t(), [known_measurement()]) :: %{
          known_measurement() => term
        }
  def take(context, keys) when is_list(keys) do
    [{_, ets}] = Registry.lookup(context.registry, :measurement_ets)

    Enum.reduce(keys, %{}, fn key, results ->
      case :ets.lookup(ets, key) do
        [{^key, val}] ->
          Map.put(results, key, val)

        _ ->
          results
      end
    end)
  end

  def dump(context) do
    [{_, ets}] = Registry.lookup(context.registry, :measurement_ets)

    ets
    |> :ets.tab2list()
    |> Enum.sort()
  end

  def start_link(%{context: context}) do
    GenServer.start_link(__MODULE__, context,
      name: CoffeeTime.Application.name(context, __MODULE__)
    )
  end

  def init(context) do
    ets =
      :ets.new(:measurements, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    Registry.register(context.registry, :measurement_ets, ets)

    state = %__MODULE__{context: context, ets: ets}
    {:ok, state}
  end
end
