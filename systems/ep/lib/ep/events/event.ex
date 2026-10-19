defmodule Ep.Events.Event do
  @moduledoc false
  use Ep.Schema

  schema "event" do
    field :scope_key, :string
    field :scope, :string
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :stream_type, :string
    field :stream_id, :binary_id
    field :stream_version, :integer
    field :event_type, :string
    field :schema_version, :integer, default: 1
    field :actor_identity_id, :binary_id
    field :command_id, :binary_id
    field :correlation_id, :binary_id
    timestamps()
  end
end
