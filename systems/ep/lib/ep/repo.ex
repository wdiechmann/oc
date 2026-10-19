defmodule Ep.Repo do
  use Ecto.Repo,
    otp_app: :ep,
    adapter: Ecto.Adapters.Postgres
end
