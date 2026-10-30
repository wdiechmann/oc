defmodule Ep.Finance.Binding do
  use Ep.Schema

  schema "finance_binding" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :occasion_id, :binary_id
    timestamps()
  end
end
