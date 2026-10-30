defmodule Ep.Finance.Steward do
  use Ep.Schema

  schema "finance_steward" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :identity_id, :binary_id
    field :can_reopen_periods, :boolean, default: false
    field :active, :boolean, default: true
    timestamps()
  end
end
