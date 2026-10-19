Rails.application.routes.draw do
  root "tenants#index"
  resource :session, only: %i[new create destroy]
  resources :magic_links, only: :create
  resources :tenants, only: %i[index create show]
  post "open_tenant", to: "tenants#open"
  get "up" => "rails/health#show", as: :rails_health_check
end
