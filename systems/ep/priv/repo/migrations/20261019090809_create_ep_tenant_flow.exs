defmodule Ep.Repo.Migrations.CreateEpTenantFlow do
  use Ecto.Migration

  def change do
    create table(:party, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :text, null: false
      add :status, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:identity, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :party_id, references(:party, type: :uuid), null: false
      add :email, :text, null: false
      add :status, :text, null: false
      add :verified_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:identity, [:party_id])
    create unique_index(:identity, [:email])

    create table(:magic_link, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :text, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:magic_link, [:token_hash])
    create index(:magic_link, [:email, :inserted_at])

    create table(:identity_session, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :identity_id, references(:identity, type: :uuid), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:identity_session, [:token_hash])
    create index(:identity_session, [:identity_id])

    create table(:tenant, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :creator_identity_id, references(:identity, type: :uuid), null: false
      add :status, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:tenant_access, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :role, :text, null: false
      add :status, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_access, [:tenant_id, :identity_id])
    create index(:tenant_access, [:identity_id, :status])

    create table(:command_receipt, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :identity_id, references(:identity, type: :uuid), null: false
      add :command_type, :text, null: false
      add :idempotency_key, :text, null: false
      add :fingerprint, :binary, null: false
      add :result, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_receipt, [:identity_id, :command_type, :idempotency_key])

    create table(:stream_head, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :scope_key, :text, null: false
      add :stream_type, :text, null: false
      add :stream_id, :uuid, null: false
      add :version, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:stream_head, [:scope_key, :stream_type, :stream_id])
    create constraint(:stream_head, :nonnegative_version, check: "version >= 0")

    create table(:event, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :scope_key, :text, null: false
      add :scope, :text, null: false
      add :tenant_id, references(:tenant, type: :uuid)
      add :occasion_id, :uuid
      add :stream_type, :text, null: false
      add :stream_id, :uuid, null: false
      add :stream_version, :bigint, null: false
      add :event_type, :text, null: false
      add :schema_version, :integer, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :command_id, :uuid, null: false
      add :correlation_id, :uuid, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event, [:scope_key, :stream_type, :stream_id, :stream_version])
    create index(:event, [:tenant_id, :stream_version])

    create constraint(:event, :positive_versions,
             check: "stream_version > 0 AND schema_version > 0"
           )

    # Occasion-scoped writes are deliberately unavailable in this first slice.
    create constraint(:event, :valid_scope,
             check:
               "(scope = 'global' AND tenant_id IS NULL AND occasion_id IS NULL AND scope_key = 'global') OR (scope = 'tenant' AND tenant_id IS NOT NULL AND occasion_id IS NULL AND scope_key = 'tenant:' || tenant_id::text)"
           )

    create table(:event_details, primary_key: false) do
      add :event_id, references(:event, type: :uuid), primary_key: true
      add :payload, :map, null: false
    end

    create table(:outbox, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :event_id, references(:event, type: :uuid), null: false
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:outbox, [:event_id])
    create index(:outbox, [:tenant_id], where: "delivered_at IS NULL")

    create table(:consumer_inbox, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :consumer, :text, null: false
      add :event_id, references(:event, type: :uuid), null: false
      add :tenant_id, references(:tenant, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:consumer_inbox, [:consumer, :event_id])

    create table(:mv_control, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :name, :text, null: false
      add :state, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mv_control, [:tenant_id, :name])
    create constraint(:mv_control, :valid_state, check: "state IN ('running', 'stopped')")

    create table(:tenant_directory, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :name, :text, null: false
      add :source_version, :bigint, null: false
      add :last_event_id, references(:event, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_directory, [:tenant_id])
  end
end
