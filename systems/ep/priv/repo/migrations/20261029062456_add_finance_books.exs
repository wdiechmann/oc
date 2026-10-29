defmodule Ep.Repo.Migrations.AddFinanceBooks do
  use Ecto.Migration

  def change do
    create table(:finance_book, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :parent_book_id, :uuid
      add :name, :text, null: false
      add :code, :text, null: false
      add :base_currency, :text, null: false
      add :accounting_authority, :text, null: false
      add :timezone, :text, null: false
      add :fiscal_year_start_month, :integer, null: false
      add :status, :text, null: false, default: "draft"
      add :version, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_book, [:tenant_id, :code])
    create unique_index(:finance_book, [:tenant_id, :id])

    execute "ALTER TABLE finance_book ADD CONSTRAINT finance_book_parent_scope_fk FOREIGN KEY (tenant_id,parent_book_id) REFERENCES finance_book(tenant_id,id)",
            "ALTER TABLE finance_book DROP CONSTRAINT finance_book_parent_scope_fk"

    create constraint(:finance_book, :finance_book_month,
             check: "fiscal_year_start_month BETWEEN 1 AND 12"
           )

    create constraint(:finance_book, :finance_book_version, check: "version >= 0")

    create table(:finance_book_view, primary_key: false) do
      add :book_id, :uuid, primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :source_version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    execute "ALTER TABLE finance_book_view ADD CONSTRAINT finance_book_view_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
            "ALTER TABLE finance_book_view DROP CONSTRAINT finance_book_view_scope_fk"

    create index(:finance_book_view, [:tenant_id])
  end
end
