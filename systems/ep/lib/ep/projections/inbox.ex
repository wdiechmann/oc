defmodule Ep.Projections.Inbox do
  @moduledoc false
  use Ep.Schema

  schema "consumer_inbox" do
    field :consumer, :string
    field :event_id, :binary_id
    field :tenant_id, :binary_id
    timestamps()
  end
end
