defmodule Ep.Monitoring.Alert do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_alert" do
    field :rule_id, :binary_id
    field :issue_id, :binary_id
    field :trigger_event_id, :binary_id
    field :attempt_id, :binary_id
    field :state, :string
    field :claim_request_id, :binary_id
    field :claimed_until, :utc_datetime_usec
    timestamps()
  end
end
