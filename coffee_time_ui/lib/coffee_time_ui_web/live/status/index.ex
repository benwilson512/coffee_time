defmodule CoffeeTimeUiWeb.Status.Index do
  use CoffeeTimeUiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # status = CoffeeTimeFirmware.status()
    data = %{
      index: 0,
      labels: [],
      points: %{
        "Boiler Temp" => [],
        "CPU Temp" => []
      }
    }

    Process.send_after(self(), :tick, 1000)
    {:ok, assign(socket, :data, data)}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1000)
    status = CoffeeTimeFirmware.status()

    data = update_data(socket.assigns.data, status)

    socket =
      socket
      |> push_event("points", data)

    {:noreply, assign(socket, :data, data)}
  end

  defp update_data(data, status) do
    index = data.index + 1

    labels = append_and_limit(data.labels, index, 100)

    %{
      index: index,
      labels: labels,
      points: %{
        "Boiler Temp" => append_and_limit(data.points["Boiler Temp"], status[:boiler_temp], 100),
        "CPU Temp" => append_and_limit(data.points["CPU Temp"], status[:cpu_temp], 100)
      }
    }
  end

  defp append_and_limit(list, value, limit) do
    list
    |> Enum.reverse()
    |> then(fn l -> [value | l] end)
    |> Enum.take(limit)
    |> Enum.reverse()
  end
end
