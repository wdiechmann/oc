Rails.application.routes.draw do
  root "tenants#index"
  get "monitoring", to: "monitoring#scopes", as: :monitoring
  get "operations/status", to: "operations#show", as: :operation_status
  get "tenants/:tenant_id/monitoring", to: "monitoring#index", as: :tenant_monitoring
  get "tenants/:tenant_id/monitoring/issues/:id", to: "monitoring#show", as: :tenant_monitoring_issue
  post "tenants/:tenant_id/monitoring/issues/:id/actions", to: "monitoring#update", as: :tenant_monitoring_issue_action
  get "recruitment/received", to: "recruitment_intake#received", as: :recruitment_received
  get "recruitment/:tenant_id/:slug", to: "recruitment_intake#show", as: :recruitment
  post "recruitment/:tenant_id/:slug/applications", to: "recruitment_intake#create", as: :recruitment_applications
  resources :invitations, only: :index
  resource :session, only: %i[new create destroy] do
    get :verify
    get :confirm
  end
  resources :magic_links, only: :create
  resources :tenants, only: %i[index create show] do
    resources :admin_invitations, only: %i[index create] do
      post :revoke, on: :member
      post :accept, on: :member
    end
    resources :occasions, only: %i[new create show] do
      resource :recruitment, only: :show, controller: "recruitment" do
        post :open
        post :close
      end
      resources :admin_invitations, only: %i[index create] do
        post :revoke, on: :member
        post :accept, on: :member
      end
    end
  end
  post "open_tenant", to: "tenants#open"
  get "up" => "rails/health#show", as: :rails_health_check
end
