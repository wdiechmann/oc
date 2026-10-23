defmodule Ep.Monitoring.Source do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_source" do
    field :backend_id, :string
    field :identity_id, :binary_id
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :status, :string
    timestamps()
  end
end
