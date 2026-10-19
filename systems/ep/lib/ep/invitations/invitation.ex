defmodule Ep.Invitations.Invitation do
  @moduledoc false
  use Ep.Schema

  schema "tenant_admin_invitation" do
    field :tenant_id, :binary_id
    field :email, :string
    field :inviter_identity_id, :binary_id
    field :accepted_identity_id, :binary_id
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps()
  end
end
