# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

config :coffee_time, target: :host

config :coffee_time, timezone: "America/New_York"

config :logger, format: "$time $metadata[$level] $message\n"

import_config "./#{Mix.env()}.exs"
