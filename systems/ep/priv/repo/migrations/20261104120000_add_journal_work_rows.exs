defmodule Ep.Repo.Migrations.AddJournalWorkRows do
  use Ecto.Migration

  def change do
    create table(:finance_journal_counter, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :last_number, :bigint, null: false, default: 0
    end

    create table(:finance_journal_row, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, :uuid, null: false
      add :draft_id, :uuid, null: false
      add :posting_id, :bigint, null: false
      add :data, :map, null: false
    end

    create unique_index(:finance_journal_row, [:book_id, :posting_id])

    execute "ALTER TABLE finance_journal_row ADD CONSTRAINT journal_row_draft_fk FOREIGN KEY (draft_id) REFERENCES finance_journal_draft(id) DEFERRABLE INITIALLY DEFERRED",
            "ALTER TABLE finance_journal_row DROP CONSTRAINT journal_row_draft_fk"

    execute "ALTER TABLE finance_journal_row ADD CONSTRAINT journal_row_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
            "ALTER TABLE finance_journal_row DROP CONSTRAINT journal_row_book_scope_fk"

    create table(:finance_journal_attachment, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, :uuid, null: false
      add :row_id, references(:finance_journal_row, type: :uuid), null: false
      add :filename, :text, null: false
      add :content_type, :text, null: false
      add :sha256, :text, null: false
      add :byte_size, :bigint, null: false
      add :bytes, :binary, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_journal_attachment, [:book_id, :row_id])
  end
end
