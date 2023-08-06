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
    %{hold_mode: hold_mode, threshold: threshold} =
      CoffeeTime.Boiler.TempControl.reheat_status(socket.assigns.context)

    socket =
      socket
      |> assign(key, to_string(trunc(value)))
      |> assign(:hold_mode, hold_mode)
      |> assign(:threshold, threshold)

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
