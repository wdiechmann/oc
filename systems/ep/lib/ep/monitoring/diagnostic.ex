defmodule Ep.Monitoring.Diagnostic do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:event_id, :binary_id, autogenerate: false}
  schema "monitoring_diagnostic" do
    field :payload, :map
    timestamps(type: :utc_datetime_usec)
  end
end
