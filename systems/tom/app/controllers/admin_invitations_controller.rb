class AdminInvitationsController < ApplicationController
  before_action :require_session

  def index
    render_list
  end

  def create
    unless session[:admin_invitation_tenant] == params[:tenant_id] && session[:admin_invitation_key].present? && ActiveSupport::SecurityUtils.secure_compare(session[:admin_invitation_key], params[:idempotency_key].to_s)
      redirect_to tenant_admin_invitations_path(params[:tenant_id]), alert: "Open a new invitation form and try again."
      return
    end
    ep.invite_admin(params[:tenant_id], params[:email].to_s.strip, session[:admin_invitation_key])
    session.delete(:admin_invitation_key)
    redirect_to tenant_admin_invitations_path(params[:tenant_id]), notice: "Invitation recorded. The recipient must sign in with the invited email and accept before receiving access.", status: :see_other
  end

  def revoke
    ep.invitation_action(params[:tenant_id], params[:id], "revoke", "revoke-invitation:#{params[:id]}")
    redirect_to tenant_admin_invitations_path(params[:tenant_id]), notice: "Invitation revoked. No administrator access was granted.", status: :see_other
  end

  def accept
    result = ep.invitation_action(params[:tenant_id], params[:id], "accept", "accept-invitation:#{params[:id]}")
    redirect_to tenant_path(result.fetch("tenant_id")), notice: "Invitation accepted. Your tenant-admin grant has been recorded.", status: :see_other
  end

  private

  def backend_error(error)
    messages = {
      "already_invited" => "An active invitation already exists for that email.",
      "already_admin" => "This person already has tenant-admin access.",
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
    invitations = ep.admin_invitations(params[:tenant_id]).fetch("invitations")
    if session[:admin_invitation_tenant] != params[:tenant_id] || session[:admin_invitation_key].blank?
      session[:admin_invitation_tenant] = params[:tenant_id]
      session[:admin_invitation_key] = SecureRandom.uuid
    end
    render Views::Invitations::Manage.new(tenant_id: params[:tenant_id], invitations: invitations, key: session[:admin_invitation_key], email: params[:email], signed_in: true, notice: flash[:notice], alert: alert), status: status
  end
end
