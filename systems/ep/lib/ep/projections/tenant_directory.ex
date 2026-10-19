defmodule Ep.Projections.TenantDirectory do
  @moduledoc false
  use Ep.Schema

  schema "tenant_directory" do
    field :tenant_id, :binary_id
    field :name, :string
    field :source_version, :integer
    field :last_event_id, :binary_id
    timestamps()
  end
end
