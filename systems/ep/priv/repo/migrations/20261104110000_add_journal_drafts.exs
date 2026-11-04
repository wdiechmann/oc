defmodule Ep.Repo.Migrations.AddJournalDrafts do
  use Ecto.Migration

  def change do
    create table(:finance_journal_state, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, :uuid, null: false
      add :version, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:finance_journal_draft, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :data, :map, null: false
      add :validation, :map, null: false
      add :contexts, :map, null: false
      add :version, :bigint, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_journal_draft, [:tenant_id, :book_id])

    create table(:finance_journal_view, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, :uuid, null: false
      add :source_version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    for table <- [:finance_journal_state, :finance_journal_draft, :finance_journal_view] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
              "ALTER TABLE #{table} DROP CONSTRAINT #{table}_book_scope_fk"
    end

    create constraint(:finance_journal_draft, :journal_positive_version, check: "version > 0")
  end
end
