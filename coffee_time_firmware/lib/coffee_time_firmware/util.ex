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
end
