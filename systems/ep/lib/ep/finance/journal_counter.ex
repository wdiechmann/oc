defmodule Ep.Finance.JournalCounter do
  use Ecto.Schema
  @primary_key {:book_id, :binary_id, autogenerate: false}
  schema "finance_journal_counter" do
    field :last_number, :integer, default: 0
  end
end
