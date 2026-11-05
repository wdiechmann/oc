defmodule Ep.Repo.Migrations.AddVatPostingAccounts do
  use Ecto.Migration

  def change do
    alter table(:finance_vat_rule) do
      add :posting_accounts, :map, null: false, default: %{}
    end
  end
end
