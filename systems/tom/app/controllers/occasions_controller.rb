class OccasionsController < ApplicationController
  before_action :require_session

  def new
    # EP's list query checks current tenant-admin authority without requiring its tenant MV.
    ep.occasions(params[:tenant_id])
    render_form
  end

  def create
    unless session[:occasion_form_tenant] == params[:tenant_id] && session[:occasion_form_key].present? && ActiveSupport::SecurityUtils.secure_compare(session[:occasion_form_key], params[:idempotency_key].to_s)
      redirect_to new_tenant_occasion_path(params[:tenant_id]), alert: "Open a new occasion form and try again."
      return
    end
    begin
      expiry = Date.iso8601(params[:expires_on].to_s)
    rescue Date::Error
      render_form(alert: "Choose a valid expiry review date.", status: :unprocessable_entity)
      return
    end
    result = ep.create_occasion(params[:tenant_id], {
      name: params[:name].to_s.strip,
      slug: params[:slug].to_s.strip,
      expires_at: "#{expiry.iso8601}T23:59:59.000000Z",
      assign_self_as_admin: params[:assign_self_as_admin] == "1"
    }, session[:occasion_form_key])
    session.delete(:occasion_form_key)
    session.delete(:occasion_form_tenant)
    redirect_to tenant_occasion_path(params[:tenant_id], result.fetch("occasion_id")), status: :see_other
  end

  def show
    occasion = ep.occasion(params[:tenant_id], params[:id])
    render Views::Occasions::Show.new(occasion: occasion, tenant_id: params[:tenant_id], occasion_id: params[:id], signed_in: true)
  end

  private

  def backend_error(error)
    messages = {
      "slug_taken" => "That short name is already used in this tenant. Choose another.",
      "invalid_name" => "Enter an occasion name of 1–120 characters.",
      "invalid_slug" => "Use a short name with lowercase letters, numbers and hyphens.",
      "invalid_expiry" => "Choose a future expiry review date."
    }
    if action_name == "create" && messages.key?(error.code)
      render_form(alert: messages.fetch(error.code), status: error.status)
    else
      super
    end
  end

  def render_form(alert: flash[:alert], status: :ok)
    if session[:occasion_form_tenant] != params[:tenant_id] || session[:occasion_form_key].blank?
      session[:occasion_form_tenant] = params[:tenant_id]
      session[:occasion_form_key] = SecureRandom.uuid
    end
    render Views::Occasions::New.new(tenant_id: params[:tenant_id], key: session[:occasion_form_key], values: params.permit(:name, :slug, :expires_on, :assign_self_as_admin).to_h, signed_in: true, alert: alert), status: status
  end
end
