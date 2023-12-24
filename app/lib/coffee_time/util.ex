defmodule CoffeeTime.Util do
  require Logger

  def send_after(dest, msg, time, opts \\ [])

  def send_after(_dest, _msg, :infinity, _) do
    :infinity
  end

  def send_after(dest, msg, time, opts) do
    Process.send_after(dest, msg, time, opts)
  end

  def cancel_timer(:infinity), do: :ok

  def cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
  end

  def cancel_self_timer(%{} = map, key) do
    if timer = Map.fetch!(map, key) do
      cancel_timer(timer)
    end

    %{map | key => nil}
  end

  def start_self_timer(%_{} = map, key, msg, timeout, opts \\ []) when is_atom(key) do
    Map.update!(map, key, fn
      nil ->
        send_after(self(), msg, timeout, opts)

      existing ->
        existing
    end)
  end

  def receive_inspect_loop() do
    receive do
      x ->
        IO.inspect(x)
        receive_inspect_loop()
    end
  end

  def log_state_change(module, old_state, new_state) do
    name = module |> Module.split() |> List.last()

    Logger.debug("""
    #{name} Transitioning from:
    Old: #{inspect(unwrap_state(old_state))}
    New: #{inspect(unwrap_state(new_state))}
    """)
  end

  defp unwrap_state(state) when is_atom(state), do: state
  defp unwrap_state(state) when is_tuple(state), do: elem(state, 0)
end
