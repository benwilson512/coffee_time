import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :coffee_time_ui, CoffeeTimeUiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fg06YbgVJfV+Qi9tjFcGJynTVucIn3c5eO2I3KIrr1g+LejGT/zPs7+0GwRt+rUu",
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
