defmodule Ep.Monitoring.Pending do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:event_id, :binary_id, autogenerate: false}
  schema "monitoring_pending" do
    field :issue_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
