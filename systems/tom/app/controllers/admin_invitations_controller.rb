class AdminInvitationsController < ApplicationController
  before_action :require_session

  def index
    render_list
  end

  def create
    unless session[:admin_invitation_tenant] == params[:tenant_id] && session[:admin_invitation_occasion] == params[:occasion_id] && session[:admin_invitation_key].present? && ActiveSupport::SecurityUtils.secure_compare(session[:admin_invitation_key], params[:idempotency_key].to_s)
      redirect_to management_path, alert: "Open a new invitation form and try again."
      return
    end
    ep.invite_admin(params[:tenant_id], params[:email].to_s.strip, session[:admin_invitation_key], occasion_id: params[:occasion_id])
    session.delete(:admin_invitation_key)
    redirect_to management_path, notice: "Invitation recorded. The recipient must sign in with the invited email and accept before receiving access.", status: :see_other
  end

  def revoke
    ep.invitation_action(params[:tenant_id], params[:id], "revoke", "revoke-invitation:#{params[:id]}", occasion_id: params[:occasion_id])
    redirect_to management_path, notice: "Invitation revoked. No administrator access was granted.", status: :see_other
  end

  def accept
    result = ep.invitation_action(params[:tenant_id], params[:id], "accept", "accept-invitation:#{params[:id]}", occasion_id: params[:occasion_id])
    target = result["occasion_id"] ? tenant_occasion_path(result.fetch("tenant_id"), result.fetch("occasion_id")) : tenant_path(result.fetch("tenant_id"))
    redirect_to target, notice: "Invitation accepted. Your #{params[:occasion_id] ? 'occasion' : 'tenant'}-admin grant has been recorded.", status: :see_other
  end

  private

  def management_path
    params[:occasion_id] ? tenant_occasion_admin_invitations_path(params[:tenant_id], params[:occasion_id]) : tenant_admin_invitations_path(params[:tenant_id])
  end

  def backend_error(error)
    messages = {
      "already_invited" => "An active invitation already exists for that email.",
      "already_admin" => "This person already has administrator access for this scope.",
      "invalid_email" => "Enter a valid email address."
    }
    if action_name == "create" && messages.key?(error.code)
      render_list(alert: messages.fetch(error.code), status: error.status)
    elsif error.code == "invitation_unavailable"
      render Views::Error.new(message: "This invitation has expired, been revoked or already been used.", signed_in: true), status: :conflict
    else
      super
    end
  end

  def render_list(alert: flash[:alert], status: :ok)
    listing = ep.admin_invitations(params[:tenant_id], occasion_id: params[:occasion_id])
    invitations = listing.fetch("invitations")
    if session[:admin_invitation_tenant] != params[:tenant_id] || session[:admin_invitation_occasion] != params[:occasion_id] || session[:admin_invitation_key].blank?
      session[:admin_invitation_tenant] = params[:tenant_id]
      session[:admin_invitation_occasion] = params[:occasion_id]
      session[:admin_invitation_key] = SecureRandom.uuid
    end
    render Views::Invitations::Manage.new(tenant_id: params[:tenant_id], occasion_id: params[:occasion_id], scope_name: listing["occasion_name"], invitations: invitations, key: session[:admin_invitation_key], email: params[:email], signed_in: true, notice: flash[:notice], alert: alert), status: status
  end
end
