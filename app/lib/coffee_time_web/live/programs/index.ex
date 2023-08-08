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
  def handle_event("program-click", %{"program" => program_name}, socket) do
    %{
      programs: programs,
      context: context,
      running_program: current
    } = socket.assigns

    if current && to_string(current.name) == program_name do
      :ok = CoffeeTime.Barista.halt(context)

      {:noreply, socket}
    else
      program = Enum.find(programs, &(to_string(&1.name) == program_name))

      if program do
        :ok = CoffeeTime.Barista.run_program(context, program)
      end

      # This is mildly redundant to the handle_info/2 clause
      # that tracks the running program, but it helps avoid double
      # pressing the button, and acts like an optimistic ui update
      socket = assign(socket, :running_program, program)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:broadcast, :barista, msg}, socket) do
    msg |> dbg

    socket =
      case msg do
        {:program_start, program} ->
          assign(socket, :running_program, program)

        {:program_done, _} ->
          assign(socket, :running_program, nil)
      end

    {:noreply, socket}
  end

  def program_button(assigns) do
    assigns =
      assign(
        assigns,
        :current,
        assigns.running_program && assigns.running_program.name == assigns.program.name
      )

    ~H"""
    <.progress_button
      phx-click={JS.push("program-click", value: %{program: @program.name})}
      disabled={@running_program && !@current}
    >
      <.icon name={if @running_program && @current, do: "hero-pause-solid", else: "hero-play-solid"} />
      <%= format_name(@program) %>
    </.progress_button>
    """
  end

  defp format_name(program) do
    program.name
    |> to_string
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
