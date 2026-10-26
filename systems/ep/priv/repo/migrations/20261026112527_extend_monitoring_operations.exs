defmodule Ep.Repo.Migrations.ExtendMonitoringOperations do
  use Ecto.Migration

  def change do
    create table(:monitoring_permission, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :identity_id, references(:identity, type: :uuid), null: false
      add :scope_key, :text, null: false
      add :permission, :text, null: false
      add :status, :text, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:monitoring_permission, [:identity_id, :scope_key, :permission])

    create table(:monitoring_diagnostic, primary_key: false) do
      add :event_id, references(:event, type: :uuid), primary_key: true
      add :payload, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:monitoring_rule, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_id, references(:monitoring_source, type: :uuid), null: false
      add :code, :text, null: false
      add :threshold, :integer, null: false
      add :window_seconds, :integer, null: false
      add :cooldown_seconds, :integer, null: false
      add :enabled, :boolean, null: false, default: true
      add :suppressed_until, :utc_datetime_usec
      add :recipient_ids, {:array, :uuid}, null: false
      add :delivery_backend_id, :text, null: false
      add :version, :bigint, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:monitoring_rule, [:source_id, :code])

    create table(:monitoring_alert, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :rule_id, references(:monitoring_rule, type: :uuid), null: false
      add :issue_id, references(:monitoring_issue, type: :uuid), null: false
      add :trigger_event_id, references(:event, type: :uuid), null: false
      add :attempt_id, :uuid, null: false
      add :state, :text, null: false, default: "pending"
      add :claim_request_id, :uuid
      add :claimed_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:monitoring_alert, [:state, :inserted_at])
    create index(:monitoring_alert, [:rule_id, :inserted_at])

    create table(:monitoring_redaction, primary_key: false) do
      add :event_id, references(:event, type: :uuid), primary_key: true
      add :reason, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:monitoring_subject, primary_key: false) do
      add :event_id, references(:event, type: :uuid), primary_key: true
      add :subject_hash, :text, primary_key: true
      timestamps(type: :utc_datetime_usec)
    end

    create index(:monitoring_subject, [:subject_hash])

    create table(:monitoring_erasure, primary_key: false) do
      add :subject_hash, :text, primary_key: true
      add :state, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
