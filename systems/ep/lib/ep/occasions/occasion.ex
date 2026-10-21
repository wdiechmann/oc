defmodule Ep.Occasions.Occasion do
  @moduledoc false
  use Ep.Schema

  schema "occasion" do
    field :tenant_id, :binary_id
    field :name, :string
    field :slug, :string
    field :status, :string, default: "draft"
    field :recruitment_config, :map, default: %{}
    field :recruitment_state, :string, default: "closed"
    field :expires_at, :utc_datetime_usec
    field :creator_identity_id, :binary_id
    timestamps()
  end
end
