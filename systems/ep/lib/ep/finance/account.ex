defmodule Ep.Finance.Account do
  use Ep.Schema

  schema "finance_account" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :actor_identity_id, :binary_id
    field :application_id, :string
    field :vat_entry_id, :binary_id
    field :category_entry_id, :binary_id
    field :vat_entry_version, :integer
    field :category_entry_version, :integer
    field :vat_basis, :string
    field :vat_code, :string
    field :category, :string
    field :position, :integer
    field :formula, :string
    field :formula_refs, :map, default: %{}
    field :number, :string
    field :reserved_numbers, {:array, :string}
    field :name, :string
    field :kind, :string
    field :retired, :boolean, default: false
    field :active, :boolean, default: true
    field :version, :integer
    timestamps()
  end
end
