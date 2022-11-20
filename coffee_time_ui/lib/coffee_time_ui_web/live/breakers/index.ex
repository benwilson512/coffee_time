defmodule CoffeeTimeUiWeb.Breakers.Index do
  use CoffeeTimeUiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :breakers, [])}
  end
end
