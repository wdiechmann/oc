defmodule Ep.Repo.Migrations.AddFinanceSetup do
  use Ecto.Migration

  def change do
    create table(:finance_setup, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, references(:tenant, type: :uuid), null: false
      add :version, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:finance_steward, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :identity_id, references(:identity, type: :uuid), null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_steward, [:book_id, :identity_id])

    create table(:finance_binding, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :occasion_id, references(:occasion, type: :uuid), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_binding, [:tenant_id, :occasion_id])

    create table(:finance_account, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      add :number, :text, null: false
      add :reserved_numbers, {:array, :text}, null: false
      add :name, :text, null: false
      add :kind, :text, null: false
      add :active, :boolean, null: false, default: true
      add :version, :bigint, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_account, [:book_id, :number])

    create table(:finance_setup_view, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, :uuid, null: false
      add :source_version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    for table <- [
          :finance_setup,
          :finance_steward,
          :finance_binding,
          :finance_account,
          :finance_setup_view
        ] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
              "ALTER TABLE #{table} DROP CONSTRAINT #{table}_book_scope_fk"
    end

    execute "ALTER TABLE finance_binding ADD CONSTRAINT finance_binding_occasion_scope_fk FOREIGN KEY (tenant_id,occasion_id) REFERENCES occasion(tenant_id,id)",
            "ALTER TABLE finance_binding DROP CONSTRAINT finance_binding_occasion_scope_fk"
  end
end
