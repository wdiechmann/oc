defmodule Ep.Events.StreamHead do
  @moduledoc false
  use Ep.Schema

  schema "stream_head" do
    field :scope_key, :string
    field :stream_type, :string
    field :stream_id, :binary_id
    field :version, :integer, default: 0
    timestamps()
  end
end
