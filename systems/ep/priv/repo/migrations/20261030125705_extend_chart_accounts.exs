defmodule Ep.Repo.Migrations.ExtendChartAccounts do
  use Ecto.Migration

  def up do
    alter table(:finance_account) do
      modify :number, :text, null: true
      add :vat_code, :text
      add :category, :text
      add :position, :integer
      add :formula, :text
      add :formula_refs, :map, null: false, default: %{}
    end

    execute "UPDATE finance_account SET kind = CASE kind WHEN 'heading' THEN 'header' WHEN 'total' THEN 'calculation' ELSE kind END"

    execute "UPDATE finance_account SET formula = '' WHERE kind = 'calculation'"

    execute "WITH ordered AS (SELECT id, row_number() OVER (PARTITION BY book_id ORDER BY number NULLS LAST, id) * 100 AS pos FROM finance_account) UPDATE finance_account a SET position = o.pos FROM ordered o WHERE o.id = a.id"

    execute "UPDATE finance_account SET number = NULL WHERE kind != 'posting'"

    alter table(:finance_account) do
      modify :position, :integer, null: false
    end

    create unique_index(:finance_account, [:book_id, :position])
  end

  def down do
    raise "Chart row types and optional numbers cannot be safely downgraded automatically"
  end
end
