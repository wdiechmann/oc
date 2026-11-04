defmodule Ep.Finance.JournalRow do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "finance_journal_row" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :draft_id, :binary_id
    field :posting_id, :integer
    field :data, :map
  end
end
