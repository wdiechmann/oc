class OperationsController < ApplicationController
  before_action :require_session

  def show
    data = Monitoring::Reconciliation.read(params[:token], session)
    unless data
      render_feedback("This completion check has expired or belongs to another sign-in. Use the support reference for help.", status: 404)
      return
    end
    Monitoring::Current.correlation_id = data.fetch("correlation_id")
    Monitoring::Current.operation_id = data.fetch("operation_id")
    response.headers["X-Correlation-ID"] = Monitoring::Current.correlation_id
    result = ep.command_status(data.fetch("type"), data.fetch("key"))
    accepted = result["status"] == "accepted"
    message = accepted ? "EP confirms the action was recorded. Refresh the current view to see its result. This does not confirm message delivery." : "Completion is still unknown. Do not start a new submission; check again later or ask for help using the reference."
    if stream_request?
      Monitoring::Current.correlation_id = data.fetch("correlation_id")
      render_feedback(message, status: accepted ? 200 : 202, outcome: accepted ? "accepted" : "unknown", operation_id: data.fetch("operation_id"), check_url: accepted ? nil : operation_status_path(token: params[:token]))
    else
      render Views::Monitoring::Status.new(message: message, reference: data.fetch("correlation_id"), signed_in: true), status: accepted ? 200 : 202
    end
  end
  private
  def backend_unavailable
    data = Monitoring::Reconciliation.read(params[:token], session)
    return super unless stream_request? && data
    render_feedback("The completion check is unavailable. Do not submit the original action again yet.", status: 503, outcome: "unknown", check_url: operation_status_path(token: params[:token]), operation_id: data.fetch("operation_id"))
  end
end
