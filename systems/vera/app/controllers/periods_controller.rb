class PeriodsController < FinanceSetupController
  private

  def command_type(action) = "FinancePeriod:#{action.delete_prefix('period_')}"
  def execute_command(action, attrs, key) = ep.period_command(params[:tenant_id], params[:book_id], action.delete_prefix("period_"), attrs, key)
  def destination(_result = nil) = tenant_book_periods_path(params[:tenant_id], params[:book_id])
  def attributes_for(action, period_id)
    attrs = { expected_version: Integer(params[:expected_version], exception: false) }
    if %w[period_create period_revise].include?(action)
      attrs.merge!(name: params[:name].to_s, start_date: params[:start_date].to_s, end_date: params[:end_date].to_s)
    end
    attrs.merge!(period_id: period_id, expected_period_version: Integer(params[:expected_period_version], exception: false)) unless action == "period_create"
    attrs[:reason] = params[:reason].to_s if action == "period_reopen"
    attrs
  end
  def show_setup(status: 200, message: nil)
    data = ep.periods(params[:tenant_id], params[:book_id])
    options = { data: data, token: method(:form_token), draft: @attrs && { action: @action, attrs: @attrs }, message: message, check_url: completion_url, retry_url: retry_url }
    if request.format.turbo_stream?
      render Components::PeriodsStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Periods::Show.new(**options, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
  end
  def error_message(code)
    case code
    when "version_conflict" then "A newer period revision exists. Your submitted draft is preserved below; compare it with the accepted dates and status before saving again."
    when "period_overlap" then "Those inclusive dates overlap another period in this book. Correct the range before saving."
    when "invalid_transition" then "That action is no longer available for the current period status. Dates can only change while the period is Draft."
    when "invalid_reason" then "Give a reopening reason of 1–500 characters."
    when "invalid_period" then "Check the period name and dates. The end date must not precede the start date."
    else super
    end
  end
end
