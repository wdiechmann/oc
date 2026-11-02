defmodule Ep.Finance.ChartImport do
  use Ep.Schema

  schema "finance_chart_import" do
    field :tenant_id, :binary_id
    field :book_id, :binary_id
    field :identity_id, :binary_id
    field :application_id, :string
    field :data, :map
    field :expires_at, :utc_datetime_usec
    field :accepted_command_id, :binary_id
    timestamps()
  end
end
