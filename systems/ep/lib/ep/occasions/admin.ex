defmodule Ep.Occasions.Admin do
  @moduledoc false
  use Ep.Schema

  schema "occasion_admin" do
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :identity_id, :binary_id
    field :status, :string, default: "active"
    timestamps()
  end
end
