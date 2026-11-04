defmodule Ep.Finance.ReportDefinition do
  use Ep.Schema

  schema "finance_report_definition" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :name, :string
    field :active, :boolean, default: true
    field :definition, :map
    field :reserved_codes, :map, default: %{}
    field :version, :integer
    field :actor_identity_id, :binary_id
    field :application_id, :string
    timestamps()
  end
end
