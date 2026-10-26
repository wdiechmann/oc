defmodule Ep.Monitoring.Rule do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_rule" do
    field :source_id, :binary_id
    field :code, :string
    field :threshold, :integer
    field :window_seconds, :integer
    field :cooldown_seconds, :integer
    field :enabled, :boolean
    field :suppressed_until, :utc_datetime_usec
    field :recipient_ids, {:array, :binary_id}
    field :delivery_backend_id, :string
    field :version, :integer
    timestamps()
  end
end
