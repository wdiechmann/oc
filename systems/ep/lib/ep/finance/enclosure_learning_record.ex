defmodule Ep.Finance.EnclosureLearningRecord do
  use Ep.Schema

  schema "finance_enclosure_learning" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :row_id, :binary_id
    field :upload_id, :binary_id
    field :attachment_id, :binary_id
    field :document_sha256, :string
    field :extraction_digest, :string
    field :supplier_key, :string, default: ""
    field :extracted_text, :string
    field :extracted_fields, :map
    field :initial_guess, :map, default: %{}
    field :applied_guess, :map, default: %{}
    field :seeded, :boolean, default: false
    field :best_guess, :map, default: %{}
    field :used_values, :map, default: %{}
    field :used_event_id, :binary_id
    field :used_confirmed_at, :utc_datetime_usec
    field :guess_version, :integer, default: 1
    field :actor_identity_id, :binary_id
    field :application_id, :string
    timestamps()
  end
end
