class TenantsController < ApplicationController
  before_action :require_session

  def index
    @key = session[:create_tenant_key] ||= SecureRandom.uuid
    page Views::Tenants::Index
  end

  def create
    key = session[:create_tenant_key]
    unless key.present? && ActiveSupport::SecurityUtils.secure_compare(params[:idempotency_key].to_s, key)
      redirect_to root_path, alert: "Open a new tenant form and try again."
      return
    end
    result = ep.create_tenant(params[:name].to_s.strip, key)
    session.delete(:create_tenant_key)
    session[:last_tenant_id] = result.fetch("tenant_id")
    redirect_to tenant_path(result.fetch("tenant_id")), status: :see_other
  end

  def open
    id = params[:tenant_id].to_s.strip
    ep.tenant(id)
    session[:last_tenant_id] = id
    redirect_to tenant_path(id), status: :see_other
  end

  def show
    @tenant = ep.tenant(params[:id])
    @tenant["tenant_id"] = params[:id]
    render Views::Tenants::Show.new(tenant: @tenant, occasions: ep.occasions(params[:id]), signed_in: true), status: :ok
  end

  private

  def page_options
    { key: @key, last_tenant_id: session[:last_tenant_id] }.compact
  end
end
