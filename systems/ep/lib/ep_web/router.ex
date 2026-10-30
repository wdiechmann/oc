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
    post "/sign-in-links", AuthController, :request_sign_in
    delete "/session", AuthController, :sign_out
    post "/magic-links/verify", AuthController, :verify
  end

  scope "/api/v1/monitoring", EpWeb do
    pipe_through :api
    post "/observations", MonitoringController, :record
    post "/delivery-outcomes", MonitoringController, :delivery
    get "/catalogue", MonitoringController, :catalogue
    get "/bindings", MonitoringOperationsController, :bindings
    post "/alerts/claim", MonitoringOperationsController, :claim
    post "/alerts/:id/outcome", MonitoringOperationsController, :outcome
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

    get "/tenants/:tenant_id/finance/books/:book_id/periods", PeriodController, :index
    post "/tenants/:tenant_id/finance/books/:book_id/periods", PeriodController, :create

    patch "/tenants/:tenant_id/finance/books/:book_id/periods/:period_id",
          PeriodController,
          :revise

    post "/tenants/:tenant_id/finance/books/:book_id/periods/:period_id/open",
         PeriodController,
         :open

    post "/tenants/:tenant_id/finance/books/:book_id/periods/:period_id/close",
         PeriodController,
         :close

    post "/tenants/:tenant_id/finance/books/:book_id/periods/:period_id/reopen",
         PeriodController,
         :reopen

    post "/tenants/:tenant_id/finance/books/:book_id/setup/reopening-authority",
         FinanceSetupController,
         :reopening_authority

    get "/tenants/:tenant_id/finance/books/:book_id/setup", FinanceSetupController, :show

    post "/tenants/:tenant_id/finance/books/:book_id/setup/stewards",
         FinanceSetupController,
         :steward

    post "/tenants/:tenant_id/finance/books/:book_id/setup/bindings",
         FinanceSetupController,
         :binding

    get "/tenants/:tenant_id/finance/books/:book_id/setup/accounts",
        FinanceSetupController,
        :accounts

    post "/tenants/:tenant_id/finance/books/:book_id/setup/accounts",
         FinanceSetupController,
         :create_account

    patch "/tenants/:tenant_id/finance/books/:book_id/setup/accounts/:account_id",
          FinanceSetupController,
          :revise_account

    get "/tenants/:tenant_id/finance/books", BookController, :index
    post "/tenants/:tenant_id/finance/books", BookController, :create
    get "/tenants/:tenant_id/finance/books/:id", BookController, :show
    patch "/tenants/:tenant_id/finance/books/:id", BookController, :update

    get "/me/monitoring-access", MonitoringOperationsController, :access
    get "/tenants/:tenant_id/monitoring/sources", MonitoringOperationsController, :sources
    post "/tenants/:tenant_id/monitoring/sources", MonitoringOperationsController, :register

    post "/tenants/:tenant_id/monitoring/sources/:id/revoke",
         MonitoringOperationsController,
         :revoke

    get "/tenants/:tenant_id/monitoring/assignees", MonitoringOperationsController, :assignees
    get "/tenants/:tenant_id/monitoring/alerts", MonitoringOperationsController, :alerts

    post "/tenants/:tenant_id/monitoring/rules/:id/state",
         MonitoringOperationsController,
         :rule_state

    get "/tenants/:tenant_id/monitoring/rules", MonitoringOperationsController, :rules
    post "/tenants/:tenant_id/monitoring/rules", MonitoringOperationsController, :configure

    post "/tenants/:tenant_id/monitoring/rules/:id/suppression",
         MonitoringOperationsController,
         :suppress

    get "/tenants/:tenant_id/monitoring/observations/:id/diagnostic",
        MonitoringOperationsController,
        :diagnostic

    get "/monitoring/platform/sources", MonitoringOperationsController, :sources
    post "/monitoring/platform/sources", MonitoringOperationsController, :register
    post "/monitoring/platform/sources/:id/revoke", MonitoringOperationsController, :revoke
    get "/monitoring/platform/assignees", MonitoringOperationsController, :assignees
    get "/monitoring/platform/alerts", MonitoringOperationsController, :alerts
    post "/monitoring/platform/rules/:id/state", MonitoringOperationsController, :rule_state
    get "/monitoring/platform/rules", MonitoringOperationsController, :rules
    post "/monitoring/platform/rules", MonitoringOperationsController, :configure
    post "/monitoring/platform/rules/:id/suppression", MonitoringOperationsController, :suppress

    get "/monitoring/platform/observations/:id/diagnostic",
        MonitoringOperationsController,
        :diagnostic

    get "/monitoring/platform/issues", MonitoringOperationsController, :platform_issues
    get "/monitoring/platform/issues/:id", MonitoringOperationsController, :platform_detail

    get "/monitoring/platform/observations",
        MonitoringOperationsController,
        :platform_observations

    post "/monitoring/platform/issues/:id/actions", MonitoringController, :update_issue
    get "/monitoring/platform/timeline", MonitoringOperationsController, :platform_timeline
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
