defmodule Ep.Finance.Period do
  use Ep.Schema

  schema "finance_period" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :name, :string
    field :start_date, :date
    field :end_date, :date
    field :status, :string, default: "draft"
    field :version, :integer
    field :actor_identity_id, :binary_id
    field :application_id, :string
    field :reason, :string
    timestamps()
  end
end
