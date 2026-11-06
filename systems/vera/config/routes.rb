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
      resource :vat_rules, only: %i[show update], controller: "vat_rules" do
        get :refresh_row
        get :completion
        post :retry
      end
      resource :catalogues, only: %i[show update], controller: "catalogues" do
        get :completion
        post :retry
      end
      resource :periods, only: %i[show update], controller: "periods" do
        get :completion
        post :retry
      end
      resource :journals, only: %i[new show update], controller: "journals" do
        get :history
        get :post_dialog
        get :delete_dialog
        get :details_dialog
        get :posting_preview
        get :user_manual
        get :accounts
        post :row_preview
        post :vat_operation
        get :attachments
        post :upload_attachment
        get :download_attachment
        post :review
        get :completion
        post :retry
      end
      resource :reports, only: %i[show update], controller: "reports" do
        post :review
        post :preview
        get :completion
        post :retry
      end
      resource :formula_preview, only: %i[show create], controller: "formula_previews"
      resource :chart_order, only: %i[show update], controller: "chart_orders" do
        post :preview
        get :completion
        post :retry
      end
      resource :chart_import, only: %i[show update], controller: "chart_imports" do
        post :upload
        post :preview
        get :export
        get :template
        get :completion
        post :retry
      end
      resource :chart, only: %i[show update], controller: "chart_accounts" do
        get :completion
        post :retry
      end
      resource :setup, only: %i[show update], controller: "finance_setup" do
        get :completion
        post :retry
      end
    end
  end
  get "up" => "rails/health#show", as: :rails_health_check
  get "up/ep", to: "ep_health#show", as: :ep_health
end
