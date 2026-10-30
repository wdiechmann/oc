Rails.application.routes.draw do
  root "home#index"
  resource :session, only: %i[new create destroy] do
    post :link, action: :request_link
    get :verify
    get :confirm
  end
  resources :tenants, only: [] do
    resources :books, only: %i[index new create show update] do
      get :completion, on: :collection
      resource :setup, only: %i[show update], controller: "finance_setup" do
        get :completion
        post :retry
      end
    end
  end
  get "up" => "rails/health#show", as: :rails_health_check
  get "up/ep", to: "ep_health#show", as: :ep_health
end
