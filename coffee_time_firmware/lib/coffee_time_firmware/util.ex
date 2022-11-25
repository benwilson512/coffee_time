defmodule CoffeeTimeFirmware.Util do
  def send_after(dest, msg, time, opts \\ [])

  def send_after(_dest, _msg, :infinity, _) do
    nil
  end

  def send_after(dest, msg, time, opts) do
    Process.send_after(dest, msg, time, opts)
  end
end
