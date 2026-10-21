class RecruitmentIntakeController < ApplicationController
  before_action :require_session, only: %i[create received]

  def show
    data = ep.recruitment_landing(params[:tenant_id], params[:slug])
    if session[:ep_token].blank? && data["status"] == "ready"
      session[:recruitment_return_to] = recruitment_path(params[:tenant_id], params[:slug])
    end
    if session[:intake_scope] != scope || session[:intake_key].blank?
      session[:intake_scope], session[:intake_key] = scope, SecureRandom.uuid
    end
    render Views::Recruitment::Landing.new(data: data, tenant_id: params[:tenant_id], slug: params[:slug], key: session[:intake_key], signed_in: session[:ep_token].present?, alert: flash[:alert])
  end

  def create
    unless session[:intake_scope] == scope && session[:intake_key].present? && ActiveSupport::SecurityUtils.secure_compare(session[:intake_key], params[:idempotency_key].to_s)
      redirect_to recruitment_path(params[:tenant_id], params[:slug]), alert: "Refresh the application form and try again."
      return
    end
    data = ep.recruitment_landing(params[:tenant_id], params[:slug])
    if data["status"] != "ready"
      redirect_to recruitment_path(params[:tenant_id], params[:slug]), alert: "Recruitment information is being updated. Please review it again."
      return
    end
    result = ep.recruitment_command(params[:tenant_id], data.fetch("occasion_id"), "applications", { notice_version: params[:notice_version].to_s, acknowledge_notice: params[:acknowledge_notice] == "1" }, session[:intake_key])
    session[:last_recruitment_application] = result.fetch("application_id")
    session.delete(:intake_key)
    redirect_to recruitment_received_path, status: :see_other
  end

  def received
    unless session[:last_recruitment_application]
      redirect_to root_path
      return
    end
    render Views::Recruitment::Received.new(signed_in: true)
  end

  private

  def scope = "#{params[:tenant_id]}/#{params[:slug]}"
  def backend_error(error)
    message = {
      "recruitment_closed" => "Recruitment is currently closed for this occasion.",
      "policy_changed" => "Recruitment information has changed. Reopen the application page and review the current notice.",
      "already_applied" => "You already have an application pending review for this occasion.",
      "notice_acknowledgment_required" => "Read and acknowledge the recruitment privacy notice before applying."
    }[error.code]
    if message
      render Views::Error.new(message: message, signed_in: session[:ep_token].present?), status: error.status
    else
      super
    end
  end
end
