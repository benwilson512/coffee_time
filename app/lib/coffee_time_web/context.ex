defmodule CoffeeTimeWeb.Context do
  def on_mount(_a, _b, _c, socket) do
    context = CoffeeTime.Context.new(CoffeeTime.Application.target())
    socket = Phoenix.Component.assign(socket, :context, context)
    {:cont, socket}
  end
end
