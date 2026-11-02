defmodule Ep.Finance.CatalogueEntry do
  use Ep.Schema

  schema "finance_catalogue_entry" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :kind, :string
    field :code, :string
    field :reserved_codes, {:array, :string}
    field :name, :string
    field :active, :boolean, default: true
    field :version, :integer
    field :actor_identity_id, :binary_id
    field :application_id, :string
    timestamps()
  end
end
