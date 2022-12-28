defmodule CoffeeTimeUiWeb.Status.Index do
  use CoffeeTimeUiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # status = CoffeeTimeFirmware.status()
    status = []

    Process.send_after(self(), :tick, 1000)
    {:ok, assign(socket, :status, status)}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1000)
    # status = CoffeeTimeFirmware.status()

    status = []

    socket =
      socket
      |> push_event("data", Map.new(status))

    {:noreply, assign(socket, :status, status)}
  end
end
