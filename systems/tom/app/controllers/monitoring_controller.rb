class MonitoringController < ApplicationController
  before_action :require_session
  FILTERS = %w[occasion_id code severity state application correlation_id cursor cutoff].freeze

  def scopes
    render Views::Monitoring::Scopes.new(workspaces: ep.workspaces, platform: ep.monitoring_access["platform_monitor"], signed_in: true)
  end

  def index
    kind = params[:view] == "observations" ? "observations" : "issues"
    filters = params.slice(*FILTERS).permit(*FILTERS).to_h.reject { |_k, v| v.blank? }
    filters["state"] = "open" if kind == "issues" && !params.key?(:state)
    data = ep.monitoring_list(params[:tenant_id], kind, filters)
    options = { tenant_id: params[:tenant_id], kind: kind, filters: filters, data: data }
    if stream_request?
      render Components::UpdateStream.new(target: "monitoring-list", operation_id: request.headers["X-TOM-Operation-ID"].present? ? Monitoring::Current.operation_id : nil, component: Components::MonitoringList.new(**options)), content_type: "text/vnd.turbo-stream.html"
    else
      render Views::Monitoring::Index.new(**options, signed_in: true)
    end
  end

  def show
    data = ep.monitoring_issue(params[:tenant_id], params[:id])
    oid = data.dig("issue", "occasion_id") || params[:occasion_id]
    timeline = data["issue"] ? ep.monitoring_list(params[:tenant_id], "timeline", { issue_id: params[:id], occasion_id: oid, cursor: params[:timeline_cursor].presence }.compact) : { "items" => [] }
    prepare_key
    options = { tenant_id: params[:tenant_id], id: params[:id], occasion_id: oid, data: data, timeline: timeline, key: session[:monitoring_key], assignees: ep.monitoring_assignees(params[:tenant_id], occasion_id: oid).fetch("assignees") }
    if stream_request?
      render Components::UpdateStream.new(target: "monitoring-detail", operation_id: request.headers["X-TOM-Operation-ID"].present? ? Monitoring::Current.operation_id : nil, component: Components::MonitoringDetail.new(**options)), content_type: "text/vnd.turbo-stream.html"
    else
      render Views::Monitoring::Show.new(**options, signed_in: true)
    end
  end

  def update
    action = params[:action_name].to_s
    expected = Integer(params[:expected_version], exception: false)
    key = session[:monitoring_key]
    unless %w[acknowledge assign resolve reopen].include?(action) && expected&.positive? && session[:monitoring_issue] == "#{params[:tenant_id]}/#{params[:id]}" && key.present? && ActiveSupport::SecurityUtils.secure_compare(key, params[:idempotency_key].to_s)
      render_feedback("Refresh this issue before submitting an action.", status: 422)
      return
    end
    attributes = { action: action, expected_version: expected }
    attributes[:reason] = params[:reason].to_s if action == "resolve"
    attributes[:owner_identity_id] = params[:owner_identity_id].to_s if action == "assign"
    result = ep.monitoring_action(params[:tenant_id], params[:id], attributes, "#{key}:#{action}")
    session.delete(:monitoring_key)
    if stream_request?
      render_feedback("Action recorded at version #{result['stream_version']}. Refresh the issue to see its updated view.", status: 200, outcome: "accepted")
    else
      redirect_to monitoring_issue_path(params[:tenant_id], params[:id]), notice: "Action recorded. The view may still be updating.", status: :see_other
    end
  end

  def diagnostic
    data = ep.monitoring_diagnostic(params[:tenant_id], params[:id])
    render Views::Monitoring::Diagnostic.new(data: data, signed_in: true)
  end

  private

  def backend_error(error)
    if stream_request? && [ 401, 404 ].include?(error.status)
      reset_session if error.status == 401
      render Components::MonitoringUnavailableStream.new(message: "Monitoring is unavailable for your current access.", reference: Monitoring::Current.correlation_id), content_type: "text/vnd.turbo-stream.html", status: error.status
    else
      super
    end
  end

  def backend_unavailable
    return super unless stream_request?
    render Components::MonitoringUnavailableStream.new(message: "Monitoring is unavailable or stopped. Its previous view cannot be treated as current.", reference: Monitoring::Current.correlation_id), content_type: "text/vnd.turbo-stream.html", status: 503
  end

  def prepare_key
    scope = "#{params[:tenant_id]}/#{params[:id]}"
    if session[:monitoring_issue] != scope || session[:monitoring_key].blank?
      session[:monitoring_issue], session[:monitoring_key] = scope, SecureRandom.uuid
    end
  end
end
