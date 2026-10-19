defmodule Ep.Repo.Migrations.CreateTenantAdminInvitations do
  use Ecto.Migration

  def change do
    create table(:tenant_admin_invitation, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :email, :text, null: false
      add :inviter_identity_id, references(:identity, type: :uuid), null: false
      add :accepted_identity_id, references(:identity, type: :uuid)
      add :status, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tenant_admin_invitation, [:tenant_id, :email])
    create index(:tenant_admin_invitation, [:email, :status, :expires_at])

    create constraint(:tenant_admin_invitation, :valid_invitation_status,
             check: "status IN ('pending', 'accepted', 'revoked')"
           )
  end
end
