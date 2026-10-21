defmodule Ep.Repo.Migrations.AddRecruitmentIntake do
  use Ecto.Migration

  def change do
    alter table(:occasion) do
      add :recruitment_config, :map, null: false, default: %{}
    end

    alter table(:occasion_directory) do
      add :recruitment_config, :map, null: false, default: %{}
    end

    create table(:recruitment_application, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :occasion_id, :uuid, null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :status, :text, null: false
      add :notice_version, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:recruitment_application, [:tenant_id, :occasion_id, :identity_id])
    create index(:recruitment_application, [:tenant_id, :occasion_id, :inserted_at])

    execute "ALTER TABLE recruitment_application ADD CONSTRAINT recruitment_application_parent FOREIGN KEY (tenant_id, occasion_id) REFERENCES occasion(tenant_id, id)",
            "ALTER TABLE recruitment_application DROP CONSTRAINT recruitment_application_parent"

    create constraint(:recruitment_application, :pending_only, check: "status = 'pending_review'")
  end
end
