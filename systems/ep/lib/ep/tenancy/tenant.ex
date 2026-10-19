defmodule Ep.Tenancy.Tenant do
  @moduledoc false
  use Ep.Schema

  schema "tenant" do
    field :name, :string
    field :creator_identity_id, :binary_id
    field :status, :string, default: "active"
    timestamps()
  end
end
