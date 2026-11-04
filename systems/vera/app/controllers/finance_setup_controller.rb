class FinanceSetupController < ApplicationController
  before_action :require_finance_session
  rescue_from Ep::Client::Error, with: :setup_error

  def show
    show_setup
  end

  def update
    return pending_feedback if session[:finance_operation]
    form = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    unless form && form["scope"] == form_scope && form["nonce"] == session[:finance_form_nonce]
      return feedback("Refresh this setup form before saving.", status: 422)
    end
    @action = form.fetch("action")
    @attrs = attributes_for(@action, form["account_id"])
    session[:finance_operation] = { "tenant_id"=>params[:tenant_id], "book_id"=>params[:book_id], "type"=>command_type(@action), "key"=>form.fetch("key"), "attrs"=>@attrs.stringify_keys, "action"=>@action }
    result = execute_command(@action, @attrs, form.fetch("key"))
    session.delete(:finance_operation)
    redirect_to destination(result), notice: accepted_notice(result), status: :see_other
  end

  def retry
    op = session[:finance_operation]
    unless op && op["tenant_id"] == params[:tenant_id] && op["book_id"] == params[:book_id] && op["checked"]
      return feedback("Check the original request’s completion before retrying it.", status: 422)
    end
    @action, @attrs = op.fetch("action"), op.fetch("attrs").symbolize_keys
    result = execute_command(@action, @attrs, op.fetch("key"))
    session.delete(:finance_operation)
    redirect_to destination(result), notice: "EP confirms the original request at revision #{result.fetch('stream_version')}.", status: :see_other
  end

  def completion
    op = session[:finance_operation]
    return feedback("No setup request is available to check.", status: 404) unless op && op["tenant_id"] == params[:tenant_id] && op["book_id"] == params[:book_id]
    result = ep.book_receipt(op.fetch("type"), op.fetch("key"))
    if result["status"] == "accepted"
      @action, @attrs = op["action"], op.fetch("attrs", {}).symbolize_keys
      session.delete(:finance_operation)
      redirect_to destination(result["result"]), notice: "EP confirms your setup request was accepted.", status: :see_other
    else
      session[:finance_operation] = op.merge("checked"=>true)
      pending_feedback
    end
  end

  private

  def require_finance_session
    return if signed_in?
    reset_session
    protected_feedback("Your sign-in has expired. Sign in again before continuing.", 401)
  end
  def accepted_notice(result) = "Setup accepted at revision #{result.fetch('stream_version')}. Refresh if the view is still updating."
  def command_type(action) = "FinanceSetup:#{action}"
  def execute_command(action, attrs, key) = ep.configure_finance(params[:tenant_id], params[:book_id], action, attrs, key)
  def destination(_result = nil)
    tenant_book_setup_path(params[:tenant_id], params[:book_id])
  end
  def form_scope = "#{params[:tenant_id]}/#{params[:book_id]}"
  def form_token(action, account_id = nil)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>action, "account_id"=>account_id, "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 4.hours)
  end
  def attributes_for(action, account_id)
    attrs = { expected_version: Integer(params[:expected_version], exception: false) }
    case action
    when "steward" then attrs.merge(identity_id: params[:identity_id].to_s, active: params[:active] == "true")
    when "reopening_authority" then attrs.merge(identity_id: params[:identity_id].to_s, allow: params[:allow] == "true")
    when "binding" then attrs.merge(occasion_id: params[:occasion_id].to_s, active: params[:active] == "true")
    else
      attrs.merge!(number: params[:number].to_s, name: params[:name].to_s, kind: params[:kind].to_s)
      attrs.merge!(account_id: account_id, active: params[:active] == "true", expected_account_version: Integer(params[:expected_account_version], exception: false)) if action == "account_revise"
      attrs
    end
  end
  def show_setup(status: 200, message: nil)
    data = ep.finance_setup(params[:tenant_id], params[:book_id])
    draft = @attrs && { action: @action, attrs: @attrs }
    options = { data: data, token: method(:form_token), draft: draft, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, query: params[:q].to_s }
    if request.format.turbo_stream?
      render Components::FinanceSetupStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::FinanceSetup::Show.new(**options, notice: flash[:notice]), status: status
    end
  end
  def completion_url
    op = session[:finance_operation]
    return unless op
    if op["action"] == "journal_save"
      completion_tenant_book_journals_path(op["tenant_id"], op["book_id"])
    elsif op["action"] == "report_save"
      completion_tenant_book_reports_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("vat_rule_")
      completion_tenant_book_vat_rules_path(op["tenant_id"], op["book_id"])
    elsif op["type"] == "FinanceChartOrder:accept"
      completion_tenant_book_chart_order_path(op["tenant_id"], op["book_id"])
    elsif op["type"] == "FinanceChartImport:accept"
      completion_tenant_book_chart_import_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("catalogue_")
      completion_tenant_book_catalogues_path(op["tenant_id"], op["book_id"])
    elsif op["type"].to_s.start_with?("FinancePeriod:")
      completion_tenant_book_periods_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("account_")
      completion_tenant_book_chart_path(op["tenant_id"], op["book_id"])
    else
      completion_tenant_book_setup_path(op["tenant_id"], op["book_id"])
    end
  end
  def retry_url
    op = session[:finance_operation]
    return unless op && op["checked"]
    if op["action"] == "journal_save"
      retry_tenant_book_journals_path(op["tenant_id"], op["book_id"])
    elsif op["action"] == "report_save"
      retry_tenant_book_reports_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("vat_rule_")
      retry_tenant_book_vat_rules_path(op["tenant_id"], op["book_id"])
    elsif op["type"] == "FinanceChartOrder:accept"
      retry_tenant_book_chart_order_path(op["tenant_id"], op["book_id"])
    elsif op["type"] == "FinanceChartImport:accept"
      retry_tenant_book_chart_import_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("catalogue_")
      retry_tenant_book_catalogues_path(op["tenant_id"], op["book_id"])
    elsif op["type"].to_s.start_with?("FinancePeriod:")
      retry_tenant_book_periods_path(op["tenant_id"], op["book_id"])
    elsif op["action"].to_s.start_with?("account_")
      retry_tenant_book_chart_path(op["tenant_id"], op["book_id"])
    else
      retry_tenant_book_setup_path(op["tenant_id"], op["book_id"])
    end
  end
  def setup_error(error)
    return unavailable if error.status >= 500
    if [ 401, 403, 404 ].include?(error.status)
      preserve_receipt = error.status != 401 && session[:finance_operation] && action_name != "update"
      session.delete(:finance_operation) unless preserve_receipt
      reset_session if error.status == 401
      message = "Setup is not available for your current access."
      message += " The original request may already have been accepted; check its completion." if preserve_receipt
      return protected_feedback(message, error.status)
    end
    return pending_feedback if error.code == "idempotency_conflict"
    session.delete(:finance_operation)
    message = error_message(error.code)
    show_setup(status: error.status, message: message)
  end
  def error_message(code)
    case code
    when "version_conflict" then "A newer revision exists. Compare your draft with the accepted row below, then explicitly reapply it."
    when "position_taken" then "That position is already in use. Choose a free integer position."
    when "invalid_formula" then "Check the formula’s account references and arithmetic. Formulas cannot refer to headers or form a cycle."
    when "number_taken" then "That account number is reserved in this book. Choose another number."
    when "binding_taken" then "This occasion already belongs to another book. Its steward must unbind it first."
    else "Check the setup fields and try again."
    end
  end
  def unavailable
    if request.get? && action_name != "completion"
      protected_feedback("The setup view is unavailable or stopped. Refresh when EP is available.", 503)
    else
      pending_feedback(503)
    end
  end
  def pending_feedback(status = 200)
    feedback("The save outcome is unknown. Check completion before saving again. An absent receipt does not prove failure. After checking, you can explicitly retry the unchanged original request with its original key.", status: status)
  end
  def feedback(message, status:)
    if request.format.turbo_stream?
      render Components::FeedbackStream.new(message: message, check_url: completion_url, retry_url: retry_url), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Books::Unavailable.new(message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?), status: status
    end
  end
  def protected_feedback(message, status)
    if request.format.turbo_stream?
      render Components::BooksUnavailableStream.new(message: message, check_url: completion_url), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Books::Unavailable.new(message: message, check_url: completion_url, signed_in: signed_in?), status: status
    end
  end
end
