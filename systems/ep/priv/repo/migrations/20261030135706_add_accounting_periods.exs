defmodule Ep.Repo.Migrations.AddAccountingPeriods do
  use Ecto.Migration

  def change do
    alter table(:finance_steward) do
      add :can_reopen_periods, :boolean, null: false, default: false
    end

    create constraint(:finance_steward, :reopening_requires_active_steward,
             check: "NOT can_reopen_periods OR active"
           )

    create table(:finance_period_state, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, :uuid, null: false
      add :version, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:finance_period, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :name, :text, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :status, :text, null: false, default: "draft"
      add :version, :bigint, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      add :reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_period, [:tenant_id, :book_id, :start_date])
    create constraint(:finance_period, :ordered_dates, check: "start_date <= end_date")

    create constraint(:finance_period, :valid_status,
             check: "status IN ('draft','open','closed')"
           )

    create constraint(:finance_period, :positive_version, check: "version > 0")

    create table(:finance_period_view, primary_key: false) do
      add :book_id, references(:finance_book, type: :uuid), primary_key: true
      add :tenant_id, :uuid, null: false
      add :source_version, :bigint, null: false
      add :data, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    for table <- [:finance_period, :finance_period_state, :finance_period_view] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_book_scope_fk FOREIGN KEY (tenant_id,book_id) REFERENCES finance_book(tenant_id,id)",
              "ALTER TABLE #{table} DROP CONSTRAINT #{table}_book_scope_fk"
    end
  end
end
