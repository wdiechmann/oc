defmodule EpWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ep

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug EpWeb.ApiBoundary
end
