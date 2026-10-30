defmodule Ep.Finance.SetupView do
  use Ecto.Schema
  @primary_key {:book_id, :binary_id, autogenerate: false}
  schema "finance_setup_view" do
    field :tenant_id, :binary_id
    field :source_version, :integer
    field :data, :map
    timestamps(type: :utc_datetime_usec)
  end
end
