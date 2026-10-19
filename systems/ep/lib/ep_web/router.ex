defmodule EpWeb.Router do
  use EpWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug EpWeb.Plugs.Authenticate
  end

  scope "/health", EpWeb do
    pipe_through :api

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/api/v1/auth", EpWeb do
    pipe_through :api
    post "/magic-links", AuthController, :request_link
    post "/magic-links/verify", AuthController, :verify
  end

  scope "/api/v1", EpWeb do
    pipe_through [:api, :authenticated]
    get "/me/tenant-admin-invitations", InvitationController, :incoming
    get "/tenants/:tenant_id/admin-invitations", InvitationController, :index
    post "/tenants/:tenant_id/admin-invitations", InvitationController, :create
    post "/tenants/:tenant_id/admin-invitations/:id/revoke", InvitationController, :revoke
    post "/tenants/:tenant_id/admin-invitations/:id/accept", InvitationController, :accept
    post "/tenants/:tenant_id/occasions", OccasionController, :create
    get "/tenants/:tenant_id/occasions", OccasionController, :index
    get "/tenants/:tenant_id/occasions/:id", OccasionController, :show
    post "/tenants", TenantController, :create
    get "/tenants/:id", TenantController, :show
  end
end
