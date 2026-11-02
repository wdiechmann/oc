defmodule Ep.Finance.SetupState do
  use Ecto.Schema
  @primary_key {:book_id, :binary_id, autogenerate: false}
  schema "finance_setup" do
    field :tenant_id, :binary_id
    field :catalogues_initialized, :boolean, default: false
    field :version, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
