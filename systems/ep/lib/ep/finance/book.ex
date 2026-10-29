defmodule Ep.Finance.Book do
  use Ep.Schema

  schema "finance_book" do
    field :tenant_id, :binary_id
    field :parent_book_id, :binary_id
    field :name, :string
    field :code, :string
    field :base_currency, :string
    field :accounting_authority, :string
    field :timezone, :string
    field :fiscal_year_start_month, :integer
    field :status, :string, default: "draft"
    field :version, :integer, default: 0
    timestamps()
  end
end
