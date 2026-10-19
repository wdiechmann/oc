class ApplicationController < ActionController::Base
  layout false
  before_action :private_response
  rescue_from Ep::Client::Unavailable, with: :backend_unavailable
  rescue_from Ep::Client::Error, with: :backend_error

  private

  def private_response
    response.headers["Cache-Control"] = "no-store"
    # Preserve same-origin form origins for Rails CSRF checks; omit cross-origin referrers.
    response.headers["Referrer-Policy"] = "same-origin"
  end

  def require_session
    return if session[:ep_token].present? && session[:expires_at].to_i > Time.current.to_i
    reset_session
    redirect_to new_session_path
  end

  def ep = Ep::Client.new(token: session[:ep_token])

  def page(view, status: :ok)
    render view.new(signed_in: session[:ep_token].present?, notice: flash[:notice], alert: flash[:alert], **page_options), status: status
  end

  def page_options = {}

  def backend_unavailable
    render Views::Error.new(message: "EP is temporarily unavailable. Please try again.", signed_in: session[:ep_token].present?), status: :service_unavailable
  end

  def backend_error(error)
    if error.status == 401
      reset_session
      redirect_to new_session_path, alert: "That sign-in has expired or is invalid. Please sign in again."
    else
      message = case error.status
      when 404 then "Tenant unavailable"
      when 409 then "This request conflicts with an earlier submission. Start a new tenant form."
      when 422 then "Please check your details and try again."
      else "EP is temporarily unavailable. Please try again."
      end
      render Views::Error.new(message: message, signed_in: session[:ep_token].present?), status: [ 404, 409, 422 ].include?(error.status) ? error.status : :service_unavailable
    end
  end
end
