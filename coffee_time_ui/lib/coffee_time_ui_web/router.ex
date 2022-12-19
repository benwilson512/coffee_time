defmodule CoffeeTimeUiWeb.Router do
  use CoffeeTimeUiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {CoffeeTimeUiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CoffeeTimeUiWeb do
    pipe_through :browser

    live "/", Status.Index, :index, as: :status

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", CoffeeTimeUiWeb do
  #   pipe_through :api
  # end

  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: CoffeeTimeUiWeb.Telemetry
  end
end
