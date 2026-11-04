defmodule Ep.Repo.Migrations.AddEffectiveVatRules do
  use Ecto.Migration

  def change do
    create table(:finance_vat_rule, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :vat_entry_id, :uuid, null: false
      add :valid_from, :date, null: false
      add :valid_until, :date
      add :direction, :text, null: false
      add :rate_bps, :integer, null: false
      add :deductible_bps, :integer, null: false
      add :mappings, :map, null: false
      add :active, :boolean, null: false, default: true
      add :version, :bigint, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_vat_rule, [:book_id, :vat_entry_id, :valid_from])

    create constraint(:finance_vat_rule, :vat_rule_rates,
             check: "rate_bps BETWEEN 0 AND 10000 AND deductible_bps BETWEEN 0 AND 10000"
           )

    create constraint(:finance_vat_rule, :vat_rule_dates,
             check: "valid_until IS NULL OR valid_until >= valid_from"
           )

    create constraint(:finance_vat_rule, :vat_rule_direction,
             check: "direction IN ('input','output','reverse_charge','none')"
           )

    execute "ALTER TABLE finance_vat_rule ADD CONSTRAINT vat_rule_catalogue_scope_fk FOREIGN KEY (tenant_id,book_id,vat_entry_id) REFERENCES finance_catalogue_entry(tenant_id,book_id,id)",
            "ALTER TABLE finance_vat_rule DROP CONSTRAINT vat_rule_catalogue_scope_fk"
  end
end
