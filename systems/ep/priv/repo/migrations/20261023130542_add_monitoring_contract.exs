defmodule Ep.Repo.Migrations.AddMonitoringContract do
  use Ecto.Migration

  def change do
    # Machine identities have no human login channel or channel-verification timestamp.
    alter table(:identity) do
      modify :email, :text, null: true, from: {:text, null: false}
      modify :verified_at, :utc_datetime_usec, null: true, from: {:utc_datetime_usec, null: false}
    end

    create table(:monitoring_source, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :backend_id, :text, null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :tenant_id, references(:tenant, type: :uuid)
      add :occasion_id, :uuid
      add :status, :text, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:monitoring_source, :source_scope,
             check: "occasion_id IS NULL OR tenant_id IS NOT NULL"
           )

    execute "ALTER TABLE monitoring_source ADD CONSTRAINT monitoring_source_occasion_fk FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)",
            "ALTER TABLE monitoring_source DROP CONSTRAINT monitoring_source_occasion_fk"

    create table(:monitoring_issue, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_id, references(:monitoring_source, type: :uuid), null: false
      add :code, :text, null: false
      add :version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:monitoring_issue, [:source_id, :code])

    create table(:monitoring_pending, primary_key: false) do
      add :event_id, references(:event, type: :uuid), primary_key: true
      add :issue_id, references(:monitoring_issue, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:monitoring_pending, [:issue_id])

    create table(:monitoring_view, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :issue_id, :uuid, null: false
      add :tenant_id, :uuid
      add :occasion_id, :uuid
      add :kind, :text, null: false
      add :source_version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:monitoring_view, [:tenant_id, :kind, :inserted_at, :id])
    create index(:monitoring_view, [:tenant_id, :occasion_id, :kind])
    create index(:monitoring_view, [:issue_id, :kind])
    create index(:monitoring_view, [:data], using: :gin)
  end
end
