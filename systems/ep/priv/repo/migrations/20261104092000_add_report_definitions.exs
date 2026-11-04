defmodule Ep.Repo.Migrations.AddReportDefinitions do
  use Ecto.Migration

  def change do
    create table(:finance_report_definition, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :book_id, references(:finance_book, type: :uuid), null: false
      add :name, :text, null: false
      add :active, :boolean, null: false, default: true
      add :definition, :map, null: false
      add :reserved_codes, :map, null: false, default: %{}
      add :version, :bigint, null: false
      add :actor_identity_id, references(:identity, type: :uuid), null: false
      add :application_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_report_definition, [:tenant_id, :book_id])
  end
end
