class RecruitmentController < ApplicationController
  before_action :require_session

  def show
    render_management
  end

  def open
    return unless valid_form?("open")
    ep.recruitment_command(params[:tenant_id], params[:occasion_id], "open", {
      title: params[:title].to_s.strip, instructions: params[:instructions].to_s.strip,
      privacy_notice_url: params[:privacy_notice_url].to_s.strip,
      confirm_manual_review: params[:confirm_manual_review] == "1"
    }, session[:recruitment_key])
    completed("Recruitment opened. Applications will remain pending review.")
  end

  def close
    return unless valid_form?("close")
    ep.recruitment_command(params[:tenant_id], params[:occasion_id], "close", { reason: params[:reason].to_s.strip }, session[:recruitment_key])
    completed("Recruitment closed. New applications are blocked.")
  end

  private

  def target = tenant_occasion_recruitment_path(params[:tenant_id], params[:occasion_id])
  def scope = "#{params[:tenant_id]}/#{params[:occasion_id]}"
  def valid_form?(action)
    valid = session[:recruitment_scope] == scope && session[:recruitment_action] == action && session[:recruitment_key].present? && ActiveSupport::SecurityUtils.secure_compare(session[:recruitment_key], params[:idempotency_key].to_s)
    reject_form(target, "Refresh the recruitment form and try again.") unless valid
    valid
  end
  def completed(message)
    session.delete(:recruitment_key)
    redirect_to target, notice: message, status: :see_other
  end
  def render_management(alert: flash[:alert], status: :ok)
    data = ep.recruitment(params[:tenant_id], params[:occasion_id])
    action = data["recruitment_state"] == "open" ? "close" : "open"
    if session[:recruitment_scope] != scope || session[:recruitment_action] != action || session[:recruitment_key].blank?
      session[:recruitment_scope], session[:recruitment_action], session[:recruitment_key] = scope, action, SecureRandom.uuid
    end
    applications = ep.recruitment_applications(params[:tenant_id], params[:occasion_id]).fetch("applications")
    render Views::Recruitment::Manage.new(data: data, applications: applications, tenant_id: params[:tenant_id], occasion_id: params[:occasion_id], key: session[:recruitment_key], values: params.permit(:title, :instructions, :privacy_notice_url, :reason).to_h, signed_in: true, notice: flash[:notice], alert: alert), status: status
  end
  def backend_error(error)
    messages = {
      "invalid_title" => "Enter a recruitment title of 1–120 characters.",
      "invalid_instructions" => "Enter instructions of 1–2000 characters.",
      "invalid_privacy_notice_url" => "Enter the published HTTPS recruitment privacy notice URL.",
      "review_policy_required" => "Confirm the manual review and assignment safeguards policy.",
      "invalid_reason" => "Enter a closure reason of 1–500 characters.",
      "occasion_expired" => "This occasion has reached its expiry review deadline. Recruitment cannot be opened."
    }
    if messages.key?(error.code)
      stream_request? ? render_feedback(messages.fetch(error.code), status: error.status) : render_management(alert: messages.fetch(error.code), status: error.status)
    else
      super
    end
  end
end
