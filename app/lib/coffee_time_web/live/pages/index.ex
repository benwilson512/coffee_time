defmodule CoffeeTimeWeb.Pages.Index do
  use CoffeeTimeWeb, :live_view

  alias CoffeeTime.Measurement

  @impl true
  def mount(_params, _session, socket) do
    context = CoffeeTime.Context.new(:host)

    Measurement.Store.subscribe(context, :boiler_temp)
    Measurement.Store.subscribe(context, :cpu_temp)

    programs = CoffeeTime.Barista.list_programs(context)

    socket =
      socket
      |> assign(:cpu_temp, "-")
      |> assign(:boiler_temp, "-")
      |> assign(:context, context)
      |> assign(:programs, programs)

    {:ok, socket}
  end

  @impl true
  def handle_event("run", %{"program" => program}, socket) do
    program = Enum.find(socket.assigns.programs, &(to_string(&1.name) == program))

    if program do
      :ok = CoffeeTime.Barista.run_program(socket.assigns.context, program)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:broadcast, key, value}, socket) when key in [:boiler_temp, :cpu_temp] do
    {:noreply, assign(socket, key, to_string(trunc(value)))}
  end

  def format_name(program) do
    program.name
    |> to_string
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
