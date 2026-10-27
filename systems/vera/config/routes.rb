Rails.application.routes.draw do
  root "home#index"
  resource :session, only: %i[new create destroy] do
    post :link, action: :request_link
    get :verify
    get :confirm
  end
  get "up" => "rails/health#show", as: :rails_health_check
  get "up/ep", to: "ep_health#show", as: :ep_health
end
