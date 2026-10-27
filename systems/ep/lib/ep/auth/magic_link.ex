defmodule Ep.Auth.MagicLink do
  @moduledoc false
  use Ep.Schema

  schema "magic_link" do
    field :backend_id, :string, default: "internal"
    field :email, :string
    field :existing_identity_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    timestamps()
  end
end
