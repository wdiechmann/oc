defmodule Ep.Projections.Control do
  @moduledoc false
  use Ep.Schema

  schema "mv_control" do
    field :tenant_id, :binary_id
    field :name, :string
    field :state, :string, default: "running"
    timestamps()
  end
end
