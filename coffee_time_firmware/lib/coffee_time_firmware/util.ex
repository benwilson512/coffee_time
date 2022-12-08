defmodule CoffeeTimeFirmware.Util do
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
