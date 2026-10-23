defmodule Ep.Monitoring.View do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_view" do
    field :issue_id, :binary_id
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :kind, :string
    field :source_version, :integer
    field :data, :map
    timestamps()
  end
end
