defmodule Ep.Monitoring.Subject do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  schema "monitoring_subject" do
    field :event_id, :binary_id, primary_key: true
    field :subject_hash, :string, primary_key: true
    timestamps(type: :utc_datetime_usec)
  end
end
