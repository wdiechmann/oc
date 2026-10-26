class MonitoringSettingsController < ApplicationController
  before_action :require_session
  def index
    sources = ep.monitoring_sources(params[:tenant_id], occasion_id: params[:occasion_id])
    rules = ep.monitoring_rules(params[:tenant_id], occasion_id: params[:occasion_id])
    people = ep.monitoring_assignees(params[:tenant_id], occasion_id: params[:occasion_id])
    alerts = ep.monitoring_alerts(params[:tenant_id], occasion_id: params[:occasion_id])
    scope = "#{params[:tenant_id]}/#{params[:occasion_id]}"
    if session[:monitoring_settings_scope] != scope || session[:monitoring_settings_key].blank?
      session[:monitoring_settings_scope], session[:monitoring_settings_key] = scope, SecureRandom.uuid
    end
    content = { tenant_id: params[:tenant_id], occasion_id: params[:occasion_id], sources: sources, rules: rules.fetch("rules"),
      assignees: people.fetch("assignees"), alerts: alerts.fetch("alerts"), codes: ep.monitoring_catalogue.fetch("codes"), key: session[:monitoring_settings_key] }
    if stream_request?
      render Components::UpdateStream.new(target: "monitoring-settings", component: Components::MonitoringSettings.new(**content)), content_type: "text/vnd.turbo-stream.html"
    else
      render Views::Monitoring::Settings.new(content: content, signed_in: true)
    end
  end
  def update
    scope = "#{params[:tenant_id]}/#{params[:occasion_id]}"
    key = session[:monitoring_settings_key]
    unless session[:monitoring_settings_scope] == scope && key.present? && ActiveSupport::SecurityUtils.secure_compare(key, params[:idempotency_key].to_s)
      render_feedback("Refresh these settings before submitting a change.", status: 422)
      return
    end
    action = params[:configuration_action].to_s
    attributes = case action
    when "register" then { backend_id: params[:backend_id].to_s, occasion_id: params[:occasion_id].presence }.compact
    when "revoke" then {}
    when "rule" then { source_id: params[:source_id].to_s, code: params[:code].to_s, threshold: integer(:threshold), window_seconds: integer(:window_seconds), cooldown_seconds: integer(:cooldown_seconds), enabled: true, recipient_ids: Array(params[:recipient_ids]).map(&:to_s), delivery_backend_id: params[:delivery_backend_id].to_s }
    when "suppression"
      deadline = begin
        value = params[:until].to_s
        raise ArgumentError unless value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?\z/)
        Time.iso8601(value + (value.length == 16 ? ":00Z" : "Z")).iso8601
      rescue ArgumentError
        nil
      end
      { expected_version: integer(:expected_version), reason: "maintenance", until: deadline }
    when "rule_state" then { expected_version: integer(:expected_version), enabled: params[:enabled] == "true" }
    else
      render_feedback("Choose a supported configuration action.", status: 422)
      return
    end
    ep.monitoring_configuration(params[:tenant_id], action, attributes, "#{key}:#{action}:#{params[:record_id]}", id: params[:record_id])
    session.delete(:monitoring_settings_key)
    if stream_request?
      render_feedback("Monitoring configuration recorded. Refresh these settings to see the new state.", status: 200, outcome: "accepted")
    else
      redirect_to monitoring_settings_path(params[:tenant_id], occasion_id: params[:occasion_id]), notice: "Monitoring configuration recorded.", status: :see_other
    end
  end
  private
  def integer(name) = Integer(params[name], exception: false)
end
