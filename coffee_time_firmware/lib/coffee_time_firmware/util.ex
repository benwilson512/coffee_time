defmodule CoffeeTimeFirmware.Util do
  def send_after(dest, msg, time, opts \\ [])

  def send_after(_dest, _msg, :infinity, _) do
    nil
  end

  def send_after(dest, msg, time, opts) do
    Process.send_after(dest, msg, time, opts)
  end

  def receive_inspect_loop() do
    receive do
      x ->
        IO.inspect(x)
        receive_inspect_loop()
    end
  end
end
