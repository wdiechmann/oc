defmodule Ep.Auth.Session do
  @moduledoc false
  use Ep.Schema

  schema "identity_session" do
    field :identity_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps()
  end
end
