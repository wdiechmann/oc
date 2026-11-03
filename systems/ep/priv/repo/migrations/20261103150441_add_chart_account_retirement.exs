defmodule Ep.Repo.Migrations.AddChartAccountRetirement do
  use Ecto.Migration

  def up do
    alter table(:finance_account) do
      add :retired, :boolean, null: false, default: false
    end

    execute "ALTER TABLE finance_account ADD COLUMN position_scope uuid GENERATED ALWAYS AS (CASE WHEN retired THEN id ELSE '00000000-0000-0000-0000-000000000000'::uuid END) STORED"

    execute "ALTER TABLE finance_account ADD CONSTRAINT finance_account_retired_inactive CHECK (NOT retired OR NOT active)"

    execute "ALTER TABLE finance_account DROP CONSTRAINT finance_account_book_position_unique"

    execute "ALTER TABLE finance_account ADD CONSTRAINT finance_account_book_position_unique UNIQUE (book_id,position_scope,position) DEFERRABLE INITIALLY IMMEDIATE"
  end

  def down do
    execute "DO $$ BEGIN IF EXISTS (SELECT 1 FROM finance_account WHERE retired) THEN RAISE EXCEPTION 'Retired chart history exists; cannot restore global position uniqueness'; END IF; END $$"
    execute "ALTER TABLE finance_account DROP CONSTRAINT finance_account_book_position_unique"
    execute "ALTER TABLE finance_account DROP CONSTRAINT finance_account_retired_inactive"
    execute "ALTER TABLE finance_account DROP COLUMN position_scope"

    execute "ALTER TABLE finance_account ADD CONSTRAINT finance_account_book_position_unique UNIQUE (book_id,position) DEFERRABLE INITIALLY IMMEDIATE"

    alter table(:finance_account) do
      remove :retired
    end
  end
end
