defmodule Ep.Recruitment.Application do
  @moduledoc false
  use Ep.Schema

  schema "recruitment_application" do
    field :tenant_id, :binary_id
    field :occasion_id, :binary_id
    field :identity_id, :binary_id
    field :status, :string, default: "pending_review"
    field :notice_version, :string
    timestamps()
  end
end
