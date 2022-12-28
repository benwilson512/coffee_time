import Config

config :coffee_time_firmware, run: true

config :coffee_time_ui, CoffeeTimeUiWeb.Endpoint,
  url: [host: "coffee.local"],
  http: [port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: "HEY05EB1dFVSu6KykKHuS4rQPQzSHv4F7mGVB/gnDLrIu75wE/ytBXy2TaL3A6RA",
  live_view: [signing_salt: "AAAABjEyERMkxgDh"],
  check_origin: false,
  render_errors: [
    formats: [html: CoffeeTimeUiWeb.ErrorHTML, json: CoffeeTimeUiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CoffeeTimeUi.PubSub,
  # Start the server since we're running in a release instead of through `mix`
  server: true,
  code_reloader: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]
