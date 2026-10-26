defmodule Ep.Monitoring.Erasure do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:subject_hash, :string, autogenerate: false}
  schema "monitoring_erasure" do
    field :state, :string
    timestamps(type: :utc_datetime_usec)
  end
end
