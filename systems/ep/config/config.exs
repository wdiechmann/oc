# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ep,
  ecto_repos: [Ep.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

config :ep, :session_lifetime_seconds, 43_200

config :ep, Oban,
  repo: Ep.Repo,
  lifeline: [rescue_after: {5, :minutes}, interval: 30_000],
  queues: [default: 5, projections: 5, monitoring: 2]

# Configure the endpoint
config :ep, EpWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: EpWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ep.PubSub

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :correlation_id, :monitoring_code]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Monitoring rejects arbitrary input, but Phoenix logs parameters before validation.
# Filter every parameter value, including unexpected secret-bearing fields.
config :phoenix, :filter_parameters, {:keep, []}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
