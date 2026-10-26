class ApplicationController < ActionController::Base
  layout false
  before_action :private_response
  rescue_from StandardError, with: :unexpected_error
  rescue_from Notifications::Delivery::Error, with: :delivery_unavailable
  rescue_from Ep::Client::Unavailable, with: :backend_unavailable
  rescue_from Ep::Client::Error, with: :backend_error

  protected

  def process_action(*)
    supplied = request.headers["X-TOM-Operation-ID"].to_s
    operation_id = supplied.match?(Monitoring::Reporter::UUID) ? supplied : SecureRandom.uuid
    Monitoring::Current.set(correlation_id: SecureRandom.uuid, operation_id: operation_id, scope: nil, command: nil, reported: false) do
      response.headers["X-Correlation-ID"] = Monitoring::Current.correlation_id
      super
      if response.status >= 400 && !Monitoring::Current.reported
        code = case response.status
        when 400, 422, 429 then "request.validation_rejected"
        when 401, 403, 404 then "request.permission_denied"
        when 409 then "request.conflict"
        else "dependency.unavailable"
        end
        report_failure(code)
      end
    end
  end

  private

  def stream_request? = request.format.turbo_stream?

  def report_failure(code, exception: nil)
    Monitoring::Current.reported = true
    if controller_name.in?(%w[monitoring operations])
      Rails.logger.warn({ code: code, correlation_id: Monitoring::Current.correlation_id }.to_json)
    else
      Monitoring::Reporter.record(code, exception: exception)
    end
  end

  def render_feedback(message, status:, outcome: nil, check_url: nil, operation_id: Monitoring::Current.operation_id)
    options = { message: message, reference: Monitoring::Current.correlation_id, outcome: outcome,
      check_url: check_url, operation_id: operation_id, sign_in: status.to_i == 401 }
    if stream_request?
      render Components::FeedbackStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Error.new(message: "#{message} Reference: #{Monitoring::Current.correlation_id}", signed_in: session[:ep_token].present?), status: status
    end
  end

  def reject_form(target, message)
    report_failure("request.validation_rejected")
    stream_request? ? render_feedback(message, status: 422) : redirect_to(target, alert: message)
  end

  def unexpected_error(error)
    if error.is_a?(ActionController::InvalidAuthenticityToken) || error.is_a?(ActionController::ParameterMissing)
      report_failure("request.validation_rejected")
      render_feedback("This form could not be verified. Refresh it before trying again.", status: 422)
      return
    end
    report_failure("application.exception", exception: error)
    token = Monitoring::Reconciliation.token(session)
    message = token ? "TOM could not finish updating this view. Checking whether your request completed; do not submit it again yet." : "TOM could not complete this response. Please use the reference when requesting help."
    render_feedback(message, status: 500, outcome: "unknown", check_url: token && operation_status_path(token: token))
  end

  def private_response
    response.headers["Cache-Control"] = "no-store"
    # Preserve same-origin form origins for Rails CSRF checks; omit cross-origin referrers.
    response.headers["Referrer-Policy"] = "same-origin"
  end

  def require_session
    return if session[:ep_token].present? && session[:expires_at].to_i > Time.current.to_i
    return_to = request.get? && request.path == invitations_path ? invitations_path : nil
    reset_session
    session[:sign_in_return_to] = return_to if return_to
    if stream_request?
      render_feedback("Your sign-in has expired. Sign in again before continuing.", status: 401)
    else
      redirect_to new_session_path
    end
  end

  def ep = Ep::Client.new(token: session[:ep_token])

  def page(view, status: :ok)
    render view.new(signed_in: session[:ep_token].present?, notice: flash[:notice], alert: flash[:alert], **page_options), status: status
  end

  def page_options = {}

  def delivery_unavailable
    return render_feedback("Delivery was not confirmed. Do not assume the message was sent; check completion before retrying.", status: 503, outcome: "unknown", check_url: (token = Monitoring::Reconciliation.token(session)) && operation_status_path(token: token)) if stream_request?
    render Views::Error.new(message: "Message delivery failed. Please try again; invitation retries reuse the same invitation.", signed_in: session[:ep_token].present?), status: :service_unavailable
  end

  def backend_unavailable
    if stream_request?
      token = Monitoring::Reconciliation.token(session)
      return render_feedback("EP is temporarily unavailable. #{token ? 'The action may already have been recorded; check completion before retrying.' : 'Please try again later.'}", status: 503, outcome: "unknown", check_url: token && operation_status_path(token: token))
    end
    render Views::Error.new(message: "EP is temporarily unavailable. Please try again.", signed_in: session[:ep_token].present?), status: :service_unavailable
  end

  def backend_error(error)
    return backend_unavailable if error.status >= 500
    if stream_request?
      reset_session if error.status == 401
      message = { 401 => "Your sign-in has expired. Sign in again.", 403 => "This action is not permitted.", 429 => "Too many requests. Wait before trying again.", 404 => "This information is unavailable for your current access.", 409 => "The request conflicts with current state. Check completion or refresh before trying again.", 422 => "Please check the form details and try again." }.fetch(error.status, "EP is temporarily unavailable. Completion is not confirmed.")
      return render_feedback(message, status: [ 401, 403, 404, 409, 422, 429 ].include?(error.status) ? error.status : 503)
    end
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
