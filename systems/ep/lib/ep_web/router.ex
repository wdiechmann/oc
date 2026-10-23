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

  scope "/api/v1/monitoring", EpWeb do
    pipe_through :api
    post "/observations", MonitoringController, :record
    post "/delivery-outcomes", MonitoringController, :delivery
    get "/catalogue", MonitoringController, :catalogue
  end

  scope "/api/v1/recruitment", EpWeb do
    pipe_through :api
    get "/:tenant_id/:slug", RecruitmentController, :landing
  end

  scope "/api/v1", EpWeb do
    pipe_through [:api, :authenticated]
    get "/tenants/:tenant_id/occasions/:occasion_id/recruitment", RecruitmentController, :manage

    post "/tenants/:tenant_id/occasions/:occasion_id/recruitment/open",
         RecruitmentController,
         :open

    post "/tenants/:tenant_id/occasions/:occasion_id/recruitment/close",
         RecruitmentController,
         :close

    post "/tenants/:tenant_id/occasions/:occasion_id/recruitment/applications",
         RecruitmentController,
         :submit

    get "/tenants/:tenant_id/occasions/:occasion_id/recruitment/applications",
        RecruitmentController,
        :applications

    get "/me/commands", MonitoringController, :command
    get "/me/commands/:id", MonitoringController, :command
    get "/tenants/:tenant_id/monitoring/issues", MonitoringController, :issues
    get "/tenants/:tenant_id/monitoring/timeline", MonitoringController, :timeline
    get "/tenants/:tenant_id/monitoring/observations", MonitoringController, :observations
    get "/tenants/:tenant_id/monitoring/issues/:id", MonitoringController, :detail
    post "/tenants/:tenant_id/monitoring/issues/:id/actions", MonitoringController, :update_issue
    get "/me/workspaces", WorkspaceController, :index
    get "/me/occasion-admin-invitations", OccasionInvitationController, :incoming

    get "/tenants/:tenant_id/occasions/:occasion_id/admin-invitations",
        OccasionInvitationController,
        :index

    post "/tenants/:tenant_id/occasions/:occasion_id/admin-invitations",
         OccasionInvitationController,
         :create

    post "/tenants/:tenant_id/occasions/:occasion_id/admin-invitations/:id/accept",
         OccasionInvitationController,
         :accept

    post "/tenants/:tenant_id/occasions/:occasion_id/admin-invitations/:id/revoke",
         OccasionInvitationController,
         :revoke

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
