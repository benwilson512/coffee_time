# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :coffee_time, target: Mix.target(), run: true
config :coffee_time, timezone: "America/New_York"

config :logger, format: "$time $metadata[$level] $message\n"

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay", fwup_conf: "config/fwup.conf"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1668309865"

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end

config :coffee_time_ui, dev_routes: true

import_config "./#{Mix.env()}.exs"
