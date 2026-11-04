defmodule Ep.Finance.JournalAttachment do
  use Ep.Schema

  schema "finance_journal_attachment" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :row_id, :binary_id
    field :filename, :string
    field :content_type, :string
    field :sha256, :string
    field :byte_size, :integer
    field :bytes, :binary
    field :actor_identity_id, :binary_id
    timestamps()
  end
end
