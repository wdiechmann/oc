Rails.application.routes.draw do
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
  get "up/ep", to: "ep_health#show", as: :ep_health
end
