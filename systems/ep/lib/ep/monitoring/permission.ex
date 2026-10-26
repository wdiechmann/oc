defmodule Ep.Monitoring.Permission do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_permission" do
    field :identity_id, :binary_id
    field :scope_key, :string
    field :permission, :string
    field :status, :string
    timestamps()
  end
end
