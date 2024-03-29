defmodule CoffeeTimeWeb.Nav.Header do
  use CoffeeTimeWeb, :live_component

  def render(assigns) do
    ~H"""
    <header class="dark:bg-milk-chocolate px-2 sm:px-4 lg:px-8">
      <div class="flex items-center justify-between py-3 text-sm">
        <div class="flex items-center gap-2 sm:gap-4">
          <a href="/">
            <img
              src="https://cdn.pixabay.com/photo/2014/11/27/12/24/coffee-547490_1280.png"
              width="36"
            />
          </a>
        </div>
        <div class="flex items-center gap-2 font-semibold leading-6 text-zinc-900">
          <span class="rounded-lg bg-pastel-gray-700 px-2 py-1">
            <.icon name="hero-cpu-chip-mini" /> <%= @cpu_temp %>°C
          </span>
          <span :if={is_nil(@fault)} class="rounded-lg bg-pastel-gray-700 px-2 py-1">
            <.icon name={
              if @hold_mode == :reheat, do: "hero-cloud-arrow-up-mini", else: "hero-cloud-mini"
            } /> <%= @boiler_pressure %>°C (<%= @threshold %>°C)
          </span>
          <span :if={@fault} class="rounded-lg bg-pastel-gray-700 px-2 py-1">
            <.icon name="hero-exclamation-triangle-mini bg-cadmium-orange" />
            <%= @fault.message %>
          </span>
        </div>
      </div>
    </header>
    """
  end

  def update(%{broadcast: {key, value}}, socket) do
    threshold =
      CoffeeTime.Boiler.PowerControl.get_target(socket.assigns.context)

    socket =
      socket
      |> assign(key, to_string(trunc(value)))
      |> assign(:hold_mode, :maintain)
      |> assign(:threshold, threshold)

    {:ok, socket}
  end

  def update(%{id: id} = assigns, socket) do
    context = assigns.context

    socket =
      socket
      |> assign(:cpu_temp, "-")
      |> assign(:boiler_pressure, "-")
      |> assign(:hold_mode, :reheat)
      |> assign(:threshold, "-")
      |> assign(:fault, CoffeeTime.Watchdog.get_fault(context))
      |> assign(:context, context)
      |> subscribe(id)

    {:ok, socket}
  end

  defp subscribe(socket, id) do
    if socket.assigns[:subscribed] do
      socket
    else
      context = socket.assigns.context
      CoffeeTimeWeb.subscribe_component(context, __MODULE__, id, :boiler_pressure)
      CoffeeTimeWeb.subscribe_component(context, __MODULE__, id, :cpu_temp)

      assign(socket, :subscribed, true)
    end
  end
end
