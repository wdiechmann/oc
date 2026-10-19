defmodule Ep.Occasions.Directory do
  @moduledoc false
  use Ep.Schema

  schema "occasion_directory" do
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :name, :string
    field :slug, :string
    field :status, :string
    field :recruitment_state, :string
    field :expires_at, :utc_datetime_usec
    field :source_version, :integer
    field :last_event_id, :binary_id
    timestamps()
  end
end
