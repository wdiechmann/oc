import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ep, Ep.Repo,
  username: "ep",
  password: "ep",
  hostname: "127.0.0.1",
  port: 55432,
  database: "ep_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ep, EpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "s3MK6/PN1Y/57IPM0TRfxnxRsxmqHByKKk3ufP3dH+CK0+kAJoQ7W3HFNjiINj5j",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Test jobs only when a test explicitly performs them.
config :ep, Oban, testing: :manual

config :ep, :magic_link_delivery, Ep.Support.MagicLinkDelivery

config :ep, :invitation_delivery, Ep.Support.InvitationDelivery
