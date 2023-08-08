defmodule CoffeeTimeWeb.Programs.Index do
  use CoffeeTimeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    context = socket.assigns.context
    programs = CoffeeTime.Barista.list_programs(context)

    socket =
      socket
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

  def format_name(program) do
    program.name
    |> to_string
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
