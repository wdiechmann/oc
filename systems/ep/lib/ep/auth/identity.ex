defmodule Ep.Auth.Identity do
  @moduledoc false
  use Ep.Schema

  schema "identity" do
    field :party_id, :binary_id
    field :email, :string
    field :status, :string, default: "active"
    field :verified_at, :utc_datetime_usec
    timestamps()
  end
end
