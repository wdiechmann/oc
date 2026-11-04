defmodule Ep.Repo.Migrations.AddVatPresetProvenanceAndAssessmentBasis do
  use Ecto.Migration

  def change do
    alter table(:finance_vat_rule) do
      add :assessment_basis, :text, null: false, default: "net"
      add :preset, :map
    end

    create constraint(:finance_vat_rule, :vat_assessment_basis,
             check:
               "assessment_basis IN ('net','import_statement') AND (assessment_basis = 'net' OR direction = 'reverse_charge')"
           )
  end
end
