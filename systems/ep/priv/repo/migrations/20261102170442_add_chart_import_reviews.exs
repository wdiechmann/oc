defmodule Ep.Repo.Migrations.AddChartImportReviews do
  use Ecto.Migration

  def up do
    create table(:finance_chart_import, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      add :data, :map, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_command_id, :uuid
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_chart_import, [:expires_at])

    execute "ALTER TABLE finance_chart_import ADD CONSTRAINT chart_import_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)"

    execute "ALTER TABLE finance_account ADD CONSTRAINT finance_account_book_position_unique UNIQUE USING INDEX finance_account_book_id_position_index DEFERRABLE INITIALLY IMMEDIATE"
  end

  def down do
    execute "ALTER TABLE finance_account DROP CONSTRAINT finance_account_book_position_unique"
    create unique_index(:finance_account, [:book_id, :position])
    drop table(:finance_chart_import)
  end
end
