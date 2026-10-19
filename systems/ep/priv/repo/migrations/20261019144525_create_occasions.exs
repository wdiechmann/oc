defmodule Ep.Repo.Migrations.CreateOccasions do
  use Ecto.Migration

  def up do
    create table(:occasion, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :name, :text, null: false
      add :slug, :text, null: false
      add :status, :text, null: false
      add :recruitment_state, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :creator_identity_id, references(:identity, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:occasion, [:tenant_id, :slug])
    create unique_index(:occasion, [:tenant_id, :id])

    create table(:occasion_admin, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :occasion_id, :uuid, null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :status, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:occasion_admin, [:tenant_id, :occasion_id, :identity_id])

    execute "ALTER TABLE occasion_admin ADD CONSTRAINT occasion_admin_parent FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)"

    create table(:occasion_directory, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :occasion_id, :uuid, null: false
      add :name, :text, null: false
      add :slug, :text, null: false
      add :status, :text, null: false
      add :recruitment_state, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :source_version, :bigint, null: false
      add :last_event_id, references(:event, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:occasion_directory, [:tenant_id, :occasion_id])

    execute "ALTER TABLE occasion_directory ADD CONSTRAINT occasion_directory_parent FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)"

    drop constraint(:event, :valid_scope)

    create constraint(:event, :valid_scope,
             check:
               "(scope = 'global' AND tenant_id IS NULL AND occasion_id IS NULL AND scope_key = 'global') OR (scope = 'tenant' AND tenant_id IS NOT NULL AND occasion_id IS NULL AND scope_key = 'tenant:' || tenant_id::text) OR (scope = 'occasion' AND tenant_id IS NOT NULL AND occasion_id IS NOT NULL AND scope_key = 'tenant:' || tenant_id::text || ':occasion:' || occasion_id::text)"
           )

    execute "ALTER TABLE event ADD CONSTRAINT event_occasion_parent FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)"
  end

  def down do
    execute "ALTER TABLE event DROP CONSTRAINT event_occasion_parent"
    drop constraint(:event, :valid_scope)

    create constraint(:event, :valid_scope,
             check:
               "(scope = 'global' AND tenant_id IS NULL AND occasion_id IS NULL AND scope_key = 'global') OR (scope = 'tenant' AND tenant_id IS NOT NULL AND occasion_id IS NULL AND scope_key = 'tenant:' || tenant_id::text)"
           )

    drop table(:occasion_directory)
    drop table(:occasion_admin)
    drop table(:occasion)
  end
end
