defmodule Ep.Events.Details do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:event_id, :binary_id, autogenerate: false}
  schema "event_details" do
    field :payload, :map
  end
end
