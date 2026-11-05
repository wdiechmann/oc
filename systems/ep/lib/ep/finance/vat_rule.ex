defmodule Ep.Finance.VatRule do
  use Ep.Schema

  schema "finance_vat_rule" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :vat_entry_id, :binary_id
    field :valid_from, :date
    field :valid_until, :date
    field :assessment_basis, :string, default: "net"
    field :preset, :map
    field :direction, :string
    field :rate_bps, :integer
    field :deductible_bps, :integer
    field :posting_accounts, :map, default: %{}
    field :mappings, :map
    field :active, :boolean, default: true
    field :version, :integer
    field :actor_identity_id, :binary_id
    field :application_id, :string
    timestamps()
  end
end
