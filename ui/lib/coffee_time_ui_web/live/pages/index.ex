defmodule CoffeeTimeUiWeb.Pages.Index do
  use CoffeeTimeUiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    context = CoffeeTime.Context.new(:host)

    programs = CoffeeTime.Barista.list_programs(context)
    socket = assign(socket, :programs, programs)

    {:ok, socket}
  end
end
