defmodule Ep.Events.Outbox do
  @moduledoc false
  use Ep.Schema

  schema "outbox" do
    field :event_id, :binary_id
    field :tenant_id, :binary_id
    field :delivered_at, :utc_datetime_usec
    timestamps()
  end
end
