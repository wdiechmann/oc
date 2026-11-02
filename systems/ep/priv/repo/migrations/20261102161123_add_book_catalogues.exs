defmodule Ep.Repo.Migrations.AddBookCatalogues do
  use Ecto.Migration

  def change do
    create table(:finance_catalogue_entry, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :kind, :text, null: false
      add :code, :text, null: false
      add :reserved_codes, {:array, :text}, null: false
      add :name, :text, null: false
      add :active, :boolean, null: false, default: true
      add :version, :bigint, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_catalogue_entry, [:tenant_id, :book_id, :id])
    create unique_index(:finance_catalogue_entry, [:book_id, :kind, "lower(code)"])
    create constraint(:finance_catalogue_entry, :valid_kind, check: "kind IN ('vat','category')")

    execute "ALTER TABLE finance_catalogue_entry ADD CONSTRAINT catalogue_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
            "ALTER TABLE finance_catalogue_entry DROP CONSTRAINT catalogue_book_scope_fk"

    alter table(:finance_setup) do
      add :catalogues_initialized, :boolean, null: false, default: false
    end

    alter table(:finance_account) do
      add :vat_entry_id, :uuid
      add :category_entry_id, :uuid
      add :vat_entry_version, :bigint
      add :category_entry_version, :bigint
    end

    for field <- [:vat_entry_id, :category_entry_id] do
      execute "ALTER TABLE finance_account ADD CONSTRAINT account_#{field}_scope_fk FOREIGN KEY (tenant_id,book_id,#{field}) REFERENCES finance_catalogue_entry(tenant_id,book_id,id)",
              "ALTER TABLE finance_account DROP CONSTRAINT account_#{field}_scope_fk"
    end
  end
end
