defmodule CoffeeTimeWeb.Boiler.Index do
  use CoffeeTimeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    data = %{
      "target_temperature" => 121,
      "maintenance_mode" => false,
      "wake_time" => ~T[04:30:00],
      "sleep_time" => ~T[16:30:00]
    }

    socket =
      socket
      |> assign(:form, to_form(data))

    {:ok, socket}
  end
end
