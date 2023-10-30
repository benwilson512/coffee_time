defmodule CoffeeTime.Boiler.PowerManager.Config do
  defstruct idle_pressure: 0,
            active_pressure: 0,
            sleep_pressure: 0,
            active_trigger_threshold: 0,
            active_duration: :infinity,
            power_saver_interval: nil
end
