defmodule Ep.Monitoring.Redaction do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:event_id, :binary_id, autogenerate: false}
  schema "monitoring_redaction" do
    field :reason, :string
    timestamps(type: :utc_datetime_usec)
  end
end
