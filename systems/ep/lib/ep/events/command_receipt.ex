defmodule Ep.Events.CommandReceipt do
  @moduledoc false
  use Ep.Schema

  schema "command_receipt" do
    field :identity_id, :binary_id
    field :command_type, :string
    field :idempotency_key, :string
    field :fingerprint, :binary
    field :result, :map
    timestamps()
  end
end
