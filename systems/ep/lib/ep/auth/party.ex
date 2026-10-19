defmodule Ep.Auth.Party do
  @moduledoc false
  use Ep.Schema

  schema "party" do
    field :kind, :string, default: "human"
    field :status, :string, default: "active"
    timestamps()
  end
end
