defmodule CoffeeTime.Watchdog.Fault do
  @derive Jason.Encoder

  @enforce_keys [:message, :occurred_at]
  defstruct [
    :message,
    :occurred_at
  ]

  def from_json!(%{"message" => message, "occurred_at" => occurred_at}) do
    {:ok, occurred_at, _} = DateTime.from_iso8601(occurred_at)
    %__MODULE__{message: message, occurred_at: occurred_at}
  end
end
