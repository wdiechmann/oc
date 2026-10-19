Rails.application.routes.draw do
  root "tenants#index"
  resources :invitations, only: :index
  resource :session, only: %i[new create destroy]
  resources :magic_links, only: :create
  resources :tenants, only: %i[index create show] do
    resources :admin_invitations, only: %i[index create] do
      post :revoke, on: :member
      post :accept, on: :member
    end
    resources :occasions, only: %i[new create show]
  end
  post "open_tenant", to: "tenants#open"
  get "up" => "rails/health#show", as: :rails_health_check
end
