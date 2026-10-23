defmodule Ep.Monitoring.Issue do
  @moduledoc false
  use Ep.Schema

  schema "monitoring_issue" do
    field :source_id, :binary_id
    field :code, :string
    field :version, :integer
    field :data, :map
    timestamps()
  end
end
