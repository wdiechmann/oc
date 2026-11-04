class FormulaPreviewsController < ApplicationController
  before_action :require_session
  rescue_from Ep::Client::Error, with: :preview_error

  def show
    render_preview(ep.formula_preview(params[:tenant_id], params[:book_id]))
  end

  def create
    raw = params[:balances]
    raise Ep::Client::Error.new(422, code: "invalid_balances") unless raw.nil? || raw.is_a?(ActionController::Parameters) && raw.keys.size <= 2000
    @balances = {}
    raw&.each_pair { |id, value| @balances[id] = value.to_s }
    balances = @balances.reject { |_, value| value.blank? }.transform_values do |value|
      value.match?(/\A-?\d{1,13}\z/) ? Integer(value, 10) : nil
    end
    data = ep.calculate_formula_preview(params[:tenant_id], params[:book_id], { expected_version: Integer(params[:expected_version], exception: false), balances: balances })
    render_preview(data)
  end

  private
  def render_preview(data, status: 200, message: nil)
    render Views::FormulaPreviews::Show.new(data: data, balances: @balances, message: message, signed_in: signed_in?), status: status
  end
  def require_session
    return if signed_in?
    reset_session
    redirect_to new_session_path, alert: "Sign in to preview chart formulas.", status: :see_other
  end
  def preview_error(error)
    return ep_error(error) if [ 401, 403, 404 ].include?(error.status)
    return unavailable if error.status >= 500
    message = case error.code
    when "version_conflict", "view_pending" then "The chart changed or is updating. Your test balances are preserved; compare the current chart and preview again."
    when "invalid_balances" then "Enter signed whole minor-unit amounts, up to ±9,000,000,000,000, for current posting accounts. Leave unknown balances blank."
    when "chart_too_large" then "Formula preview supports up to 2,000 current chart rows."
    else "The formula preview could not be calculated. Refresh the chart and try again."
    end
    data = ep.formula_preview(params[:tenant_id], params[:book_id])
    render_preview(data, status: error.status, message: message)
  rescue Ep::Client::Unavailable
    unavailable
  rescue Ep::Client::Error => current_error
    return ep_error(current_error) if [ 401, 403, 404 ].include?(current_error.status)
    feedback("The chart is updating or unavailable. Refresh before previewing formulas.", status: current_error.status >= 500 ? 503 : 409)
  end
  def unavailable
    feedback("Formula preview is temporarily unavailable. You can retry this calculation; test balances are not saved.", status: 503)
  end
end
