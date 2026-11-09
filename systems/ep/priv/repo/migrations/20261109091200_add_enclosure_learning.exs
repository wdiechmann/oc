defmodule Ep.Repo.Migrations.AddEnclosureLearning do
  use Ecto.Migration

  def change do
    create table(:finance_enclosure_learning, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :row_id, references(:finance_journal_row, type: :uuid), null: false
      add :upload_id, :uuid, null: false
      add :attachment_id, references(:finance_journal_attachment, type: :uuid)
      add :document_sha256, :text, null: false
      add :extraction_digest, :text, null: false
      add :supplier_key, :text, null: false, default: ""
      add :extracted_text, :text, null: false
      add :extracted_fields, :map, null: false
      add :initial_guess, :map, null: false, default: %{}
      add :applied_guess, :map, null: false, default: %{}
      add :seeded, :boolean, null: false, default: false
      add :best_guess, :map, null: false, default: %{}
      add :used_values, :map, null: false, default: %{}
      add :used_event_id, references(:event, type: :uuid)
      add :used_confirmed_at, :utc_datetime_usec
      add :guess_version, :bigint, null: false, default: 1
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_enclosure_learning, [:upload_id, :extraction_digest])
    create unique_index(:finance_enclosure_learning, [:attachment_id])
    create index(:finance_enclosure_learning, [:tenant_id, :book_id])
    create index(:finance_enclosure_learning, [:row_id])
    create index(:finance_enclosure_learning, [:tenant_id, :book_id, :supplier_key])

    execute "ALTER TABLE finance_enclosure_learning ADD CONSTRAINT enclosure_learning_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
            "ALTER TABLE finance_enclosure_learning DROP CONSTRAINT enclosure_learning_book_scope_fk"
  end
end
