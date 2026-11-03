class ChartOrdersController < FinanceSetupController
  def preview
    return pending_feedback if session[:finance_operation]
    attrs = { expected_version: Integer(params[:expected_version], exception: false), ordered_ids: Array(params[:ordered_ids]) }
    data = ep.preview_chart_order(params[:tenant_id], params[:book_id], attrs)
    redirect_to tenant_book_chart_order_path(params[:tenant_id], params[:book_id], review_id: data.fetch("review_id")), status: :see_other
  end

  private
  def command_type(_action) = "FinanceChartOrder:accept"
  def execute_command(_action, attrs, key) = ep.accept_chart_order(params[:tenant_id], params[:book_id], attrs, key)
  def destination(_result = nil) = tenant_book_chart_path(params[:tenant_id], params[:book_id])
  def attributes_for(_action, account_id)
    form = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    raise Ep::Client::Error.new(422, code: "invalid_review") unless form["action"] == "order_accept" && form["digest"].present? && form["expected_version"].is_a?(Integer)
    { review_id: account_id, digest: form.fetch("digest"), expected_version: form.fetch("expected_version") }
  end
  def review_token(data)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>"order_accept", "account_id"=>data.fetch("review_id"), "digest"=>data.fetch("digest"), "expected_version"=>data.fetch("expected_version"), "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 1.hour)
  end
  def show_setup(status: 200, message: nil)
    return pending_feedback if session[:finance_operation]
    data = if params[:review_id].present?
      ep.chart_order_review(params[:tenant_id], params[:book_id], params[:review_id])
    else
      ep.chart_order(params[:tenant_id], params[:book_id])
    end
    token = review_token(data) if data["review_id"] && !data["accepted_command_id"]
    render Views::ChartOrders::Show.new(data: data, token: token, message: message, signed_in: signed_in?), status: status
  end
  def unavailable
    return super unless action_name == "preview"
    render Views::ChartOrders::Failure.new(message: "The order review could not be prepared. No account positions were changed.", order_url: tenant_book_chart_order_path(params[:tenant_id], params[:book_id]), chart_url: destination, signed_in: signed_in?), status: 503
  end
  def setup_error(error)
    return super if error.status >= 500 || [ 401, 403, 404 ].include?(error.status) || error.code == "idempotency_conflict"
    session.delete(:finance_operation)
    message = case error.code
    when "version_conflict", "view_pending" then "The chart changed or is still updating. Return to the current chart, then review its order again. No ordering changes were accepted."
    when "invalid_order" then "Review requires every current account exactly once. Open the current chart order before trying again."
    when "catalogue_not_initialized" then "Initialize this book’s VAT/category catalogues before ordering."
    when "chart_too_large" then "Native ordering supports up to 2,000 current rows."
    when "review_expired" then "This order review has expired. Open the current chart order and review again."
    else "The order could not be accepted (#{error.code}). Open the current chart order and review again."
    end
    render Views::ChartOrders::Failure.new(message: message, order_url: tenant_book_chart_order_path(params[:tenant_id], params[:book_id]), chart_url: destination, signed_in: signed_in?), status: error.status
  end
end
