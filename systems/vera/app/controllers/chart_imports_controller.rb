class ChartImportsController < FinanceSetupController
  def upload
    return pending_feedback if session[:finance_operation]
    data = ep.upload_chart(params[:tenant_id], params[:book_id], ChartCsv.parse(params[:csv]).merge(create_codes: params[:create_codes] == "1", mode: params[:mode].presence || "replace"))
    redirect_to tenant_book_chart_import_path(params[:tenant_id], params[:book_id], import_id: data.fetch("import_id")), status: :see_other
  rescue ChartCsv::Invalid => error
    show_setup(status: 422, message: error.message)
  end

  def preview
    return pending_feedback if session[:finance_operation]
    mapping = params.fetch(:mapping, ActionController::Parameters.new).permit(*%w[schema_version tenant_id book_id source_version account_id account_version type number name vat_entry_id vat_code category_entry_id category_code position formula active]).to_h.reject { |_, value| value.blank? }
    data = ep.preview_chart(params[:tenant_id], params[:book_id], params[:import_id], mapping, create_codes: params[:create_codes] == "1", mode: params[:mode].presence || "replace")
    render_review(data)
  end

  def export
    data = ep.chart_export(params[:tenant_id], params[:book_id], params.permit(:q, :source_version).to_h)
    send_data ChartCsv.generate(data.fetch("columns"), data.fetch("rows")), type: "text/csv; charset=utf-8", filename: "chart-#{params[:book_id]}-r#{data.fetch('source_version')}.csv"
  end

  def template
    data = ep.chart_import_info(params[:tenant_id], params[:book_id])
    demo = { "schema_version"=>"1", "tenant_id"=>params[:tenant_id], "book_id"=>params[:book_id], "type"=>"header", "name"=>"demo", "position"=>"100", "active"=>"true" }
    send_data ChartCsv.generate(data.fetch("columns"), [ data.fetch("columns").map { |column| demo.fetch(column, "") } ]), type: "text/csv; charset=utf-8", filename: "chart-template.csv"
  end

  private

  def command_type(_action) = "FinanceChartImport:accept"
  def execute_command(_action, attrs, key) = ep.accept_chart(params[:tenant_id], params[:book_id], attrs, key)
  def destination(_result = nil) = tenant_book_chart_path(params[:tenant_id], params[:book_id])
  def attributes_for(_action, account_id)
    form = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    raise Ep::Client::Error.new(422, code: "invalid_review") unless form["action"] == "accept" && form["digest"].present? && form["expected_version"].is_a?(Integer)
    { import_id: account_id, digest: form.fetch("digest"), expected_version: form.fetch("expected_version") }
  end
  def review_token(data)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>"accept", "account_id"=>data.fetch("import_id"), "digest"=>data.fetch("digest"), "expected_version"=>data.fetch("expected_version"), "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 1.hour)
  end
  def show_setup(status: 200, message: nil)
    return pending_feedback if session[:finance_operation]
    if params[:import_id].present?
      render_review(ep.chart_import(params[:tenant_id], params[:book_id], params[:import_id]), status: status, message: message)
    else
      render_review(ep.chart_import_info(params[:tenant_id], params[:book_id]), status: status, message: message)
    end
  end
  def render_review(data, status: 200, message: nil)
    token = review_token(data) if data.dig("plan", "valid") && !data["accepted_command_id"]
    render Views::ChartImports::Show.new(data: data, token: token, message: message, signed_in: signed_in?), status: status
  end
  def setup_error(error)
    return super if error.status >= 500 || [ 401, 403, 404 ].include?(error.status) || error.code == "idempotency_conflict"
    session.delete(:finance_operation)
    id = @attrs&.fetch(:import_id, nil) || params[:import_id]
    review_url = tenant_book_chart_import_path(params[:tenant_id], params[:book_id], import_id: id) if id.present? && error.status != 410
    render Views::ChartImports::Failure.new(message: "CSV review could not continue (#{error.code}). Review the mapping again against the current chart revision. No partial import was accepted.", chart_url: destination, review_url: review_url, signed_in: signed_in?), status: error.status
  end
end
