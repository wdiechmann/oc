class ApplicationController < ActionController::Base
  layout false
  allow_browser versions: :modern
  before_action :private_response
  rescue_from StandardError, with: :unexpected_error
  rescue_from Ep::Client::Error, with: :ep_error
  rescue_from Ep::Client::Unavailable, Notifications::Delivery::Error, with: :unavailable

  private

  def private_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "same-origin"
  end
  def signed_in? = session[:ep_token].present? && session[:expires_at].to_i > Time.current.to_i
  def ep = Ep::Client.new(token: session[:ep_token])
  def page(view, **options)
    render view.new(signed_in: signed_in?, notice: flash[:notice], alert: flash[:alert], **options)
  end
  def ep_error(error)
    return unavailable if error.status >= 500
    if error.status == 401
      reset_session
      redirect_to new_session_path, alert: "Your sign-in has expired or the link is invalid. Sign in again.", status: :see_other
    else
      feedback(error.status == 422 ? "Check your email address and try again." : "This information is not available for your current access.", status: [ 403, 404, 422, 429 ].include?(error.status) ? error.status : 503)
    end
  end
  def unexpected_error(error)
    reference = request.request_id
    Rails.logger.error({ code: "vera.request_failed", exception_class: error.class.name, correlation_id: reference }.to_json)
    feedback("VERA could not complete this response. Do not assume the operation completed. Reference: #{reference}", status: error.is_a?(ActionController::InvalidAuthenticityToken) ? 422 : 500)
  end
  def unavailable
    feedback("Sign-in or EP is temporarily unavailable. Delivery or completion has not been confirmed; try again later.", status: 503)
  end
  def feedback(message, status:)
    if request.format.turbo_stream?
      render Components::FeedbackStream.new(message: message), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Sessions::New.new(alert: message), status: status
    end
  end
end
