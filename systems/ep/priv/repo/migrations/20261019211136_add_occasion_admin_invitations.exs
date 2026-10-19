defmodule Ep.Repo.Migrations.AddOccasionAdminInvitations do
  use Ecto.Migration

  def up do
    alter table(:tenant_admin_invitation) do
      add :occasion_id, :uuid
    end

    create index(:tenant_admin_invitation, [:tenant_id, :occasion_id, :email])

    execute "ALTER TABLE tenant_admin_invitation ADD CONSTRAINT invitation_occasion_parent FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)"
  end

  def down do
    execute "ALTER TABLE tenant_admin_invitation DROP CONSTRAINT invitation_occasion_parent"
    drop index(:tenant_admin_invitation, [:tenant_id, :occasion_id, :email])

    alter table(:tenant_admin_invitation) do
      remove :occasion_id
    end
  end
end
