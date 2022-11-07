defmodule CoffeeTimeUiWeb.PageController do
  use CoffeeTimeUiWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
