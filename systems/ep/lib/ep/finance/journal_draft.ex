defmodule Ep.Finance.JournalDraft do
  use Ep.Schema

  schema "finance_journal_draft" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :data, :map
    field :validation, :map
    field :contexts, :map
    field :version, :integer
    field :actor_identity_id, :binary_id
    field :application_id, :string
    timestamps()
  end
end
