defmodule CoffeeTimeWeb.Programs.Index do
  use CoffeeTimeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    context = socket.assigns.context
    CoffeeTime.PubSub.subscribe(context, :barista)
    programs = CoffeeTime.Barista.list_programs(context)

    socket =
      socket
      |> assign(:running_program, nil)
      |> assign(:programs, programs)

    {:ok, socket}
  end

  @impl true
  def handle_event("run", %{"program" => program}, socket) do
    program = Enum.find(socket.assigns.programs, &(to_string(&1.name) == program))

    if program do
      :ok = CoffeeTime.Barista.run_program(socket.assigns.context, program)
    end

    # This is mildly redundant to the handle_info/2 clause
    # that tracks the running program, but it helps avoid double
    # pressing the button, and acts like an optimistic ui update
    socket = assign(socket, :running_program, program)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:broadcast, :barista, msg}, socket) do
    socket =
      case msg do
        {:program_start, program} ->
          assign(socket, :running_program, program)

        {:program_done, _} ->
          assign(socket, :running_program, nil)
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
