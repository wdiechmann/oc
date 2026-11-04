defmodule Ep.Repo.Migrations.AddAccountVatBasis do
  use Ecto.Migration

  def change do
    alter table(:finance_account) do
      add :vat_basis, :text
    end

    create constraint(:finance_account, :account_vat_basis,
             check: "vat_basis IS NULL OR vat_basis IN ('gross','net')"
           )
  end
end
