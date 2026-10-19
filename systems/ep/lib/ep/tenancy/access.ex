defmodule Ep.Tenancy.Access do
  @moduledoc false
  use Ep.Schema

  schema "tenant_access" do
    field :tenant_id, :binary_id
    field :identity_id, :binary_id
    field :role, :string
    field :status, :string, default: "active"
    timestamps()
  end
end
