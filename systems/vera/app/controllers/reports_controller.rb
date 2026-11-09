class ReportsController < FinanceSetupController
  def new
    params[:new] = "1"
    show_setup
  end

  def run
    params[:ytd] = "1"
    show_setup
  end

  def edit
    params[:edit] = "1"
    show_setup
  end

  def review
    return pending_feedback if session[:finance_operation]
    @editing = report_values
    if params[:intent] == "add_line"
      @extra_line = true
      return show_setup
    end
    result = ep.review_report(params[:tenant_id], params[:book_id], @editing)
    redirect_to tenant_book_reports_path(params[:tenant_id], params[:book_id], review_id: result.fetch("review_id")), status: :see_other
  end
  def line_dialog
    values = report_values(keep_blank: true)
    data = ep.reports(params[:tenant_id], params[:book_id])
    raise Ep::Client::Error.new(404, code: "not_found") unless data.dig("permissions", "configure")
    raise Ep::Client::Error.new(409, code: "view_pending") unless data["status"] == "ready" && !session[:finance_operation]
    index = Integer(params[:line_index], exception: false)
    raise Ep::Client::Error.new(422, code: "invalid_report") unless index && index >= 0 && index < values["lines"].length
    values["lines"][index]["remove"] = params.dig(:lines, index.to_s, :remove)
    mode = params[:dialog_action].presence || "edit"
    raise Ep::Client::Error.new(422, code: "invalid_report") unless %w[edit delete].include?(mode)
    content = if mode == "delete"
      Components::ReportLineDeleteDialog.new(line: values["lines"][index], index: index)
    else
      Components::ReportLineDialog.new(line: values["lines"][index], index: index, accounts: data.fetch("accounts"))
    end
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end

  def preview
    @previewing = true
    raw = params[:balances]
    raise Ep::Client::Error.new(422, code: "invalid_balances") unless raw.nil? || raw.is_a?(ActionController::Parameters) && raw.keys.length <= 2000
    @balances = {}
    raw&.each_pair { |id, value| @balances[id] = value.to_s }
    balances = @balances.reject { |_, v| v.blank? }.transform_values { |v| v.match?(/\A-?\d{1,13}\z/) ? Integer(v, 10) : nil }
    @calculated = ep.preview_report(params[:tenant_id], params[:book_id], params[:report_id], { report_version: Integer(params[:report_version], exception: false), balances: balances })
    show_setup
  end

  private
  def report_values(keep_blank: false)
    raw = params[:lines]
    raise Ep::Client::Error.new(422, code: "invalid_report") unless raw.is_a?(ActionController::Parameters) && raw.keys.length <= 2001
    raise Ep::Client::Error.new(422, code: "invalid_report") unless raw.each_pair.all? { |_, line| line.is_a?(ActionController::Parameters) }
    lines = raw.each_pair.reject { |_, l| !keep_blank && l[:remove] == "1" }.map do |_, l|
      { id: l[:id].presence, code: l[:code].to_s, name: l[:name].to_s, kind: l[:kind].to_s, position: Integer(l[:position], exception: false), formula: l[:formula].to_s, account_ids: Array(l[:account_ids]).reject(&:blank?), sign: Integer(l[:sign], exception: false) }
    end.reject { |l| !keep_blank && l[:code].blank? && l[:name].blank? && l[:formula].blank? && l[:account_ids].empty? }
    { report_id: params[:report_id].presence, expected_report_version: Integer(params[:expected_report_version], exception: false), expected_version: Integer(params[:expected_version], exception: false), name: params[:name].to_s, active: params[:active] == "true", lines: lines }.deep_stringify_keys
  end

  def destination(_result = nil) = tenant_book_reports_path(params[:tenant_id], params[:book_id])
  def execute_command(_action, attrs, key) = ep.accept_report(params[:tenant_id], params[:book_id], attrs, key)
  def attributes_for(action, id)
    signed = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    raise Ep::Client::Error.new(422, code: "invalid_report") unless action == "report_save" && signed["digest"].present? && signed["expected_version"].is_a?(Integer)
    { review_id: id, expected_version: signed.fetch("expected_version"), digest: signed.fetch("digest") }
  end
  def show_setup(status: 200, message: nil)
    data = @calculated || ep.reports(params[:tenant_id], params[:book_id], { report_id: params[:report_id].presence, version: @previewing ? params[:report_version].presence : params[:version].presence, ytd: params[:ytd].presence, as_of: params[:as_of].presence })
    raise Ep::Client::Error.new(404, code: "not_found") if action_name.in?(%w[new edit]) && !data.dig("permissions", "configure")
    review_id = params[:review_id].presence || @attrs && @attrs[:review_id]
    review = ep.report_review(params[:tenant_id], params[:book_id], review_id) if review_id
    if review && params[:edit] == "1"
      plan = review.fetch("plan")
      @editing = plan.slice("report_id", "expected_report_version", "name", "active").merge("expected_version"=>review.fetch("expected_version"), "lines"=>plan.fetch("definition").fetch("lines"), "saved_accounts"=>plan.fetch("definition").fetch("accounts"))
      review = nil
    end
    token = review_token(review) if review && !review["accepted_command_id"] && data.dig("permissions", "configure") && data["status"] == "ready" && !session[:finance_operation]
    editing = @editing || (params[:edit] == "1" && data["selected"] ? data["selected"].slice("id", "name", "active").merge("report_id"=>data["selected"]["id"], "expected_report_version"=>data["selected"]["version"], "expected_version"=>data["latest_version"], "lines"=>data["selected"].dig("definition", "lines")) : nil)
    if editing && data.dig("selected", "builtin")
      editing = editing.except("id").merge("report_id" => nil, "expected_report_version" => nil)
    end
    if !data["selected"] && !review && !editing && params[:new] != "1" && !@extra_line
      return render Views::Reports::Index.new(data: data, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
    render Views::Reports::Show.new(data: data, review: review, token: token, editing: editing, balances: @balances, extra_line: @extra_line, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, notice: flash[:notice]), status: status
  end
  def review_token(review)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>"report_save", "account_id"=>review.fetch("review_id"), "digest"=>review.fetch("digest"), "expected_version"=>review.fetch("expected_version"), "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 1.hour)
  end
  def setup_error(error)
    return protected_feedback("The report line editor is unavailable. Your draft has not changed; refresh access or try again.", error.status) if action_name == "line_dialog" && ![ 401, 403, 404 ].include?(error.status)
    if error.code == "review_expired"
      session.delete(:finance_operation)
      return protected_feedback(error_message(error.code), 410)
    end
    return super if [ 401, 403, 404 ].include?(error.status) || error.code == "idempotency_conflict" || action_name.in?(%w[update retry completion])
    return unavailable if error.status >= 500
    if @editing && error.code == "version_conflict"
      current = ep.reports(params[:tenant_id], params[:book_id], { report_id: @editing["report_id"] }.compact)
      @editing["expected_version"] = current.fetch("latest_version")
      @editing["expected_report_version"] = current.dig("selected", "version")
    end
    show_setup(status: error.status, message: error_message(error.code))
  end
  def error_message(code)
    case code
    when "invalid_report", "invalid_report_reference" then "Check report names, unique line codes/positions, line types and current posting account selections. Only mapping lines select accounts; only total lines have formulas. Clear retired account selections before reviewing."
    when "report_code_reserved" then "That line code belongs to another saved line. Restore that line or choose a new code."
    when "invalid_formula" then "Total formulas reference report line codes in brackets, for example [REVENUE] - [COSTS]. References must exist and cannot point to headers or form a cycle."
    when "version_conflict" then "The chart or report changed. Compare your draft with the current accepted version and review again explicitly."
    when "external_accounting_authority" then "This book uses an external accounting authority. EP has no authoritative ledger balances to report."
    when "invalid_balances" then "Enter signed whole minor-unit test balances for the accounts in this report revision; blanks are unknown."
    when "review_expired" then "This private review expired. Review the report again before accepting."
    when "view_pending" then "The report view is still updating. Refresh before reviewing or previewing."
    when "report_limit", "chart_too_large" then "Reports support 2,000 lines, 4,000 account assignments, 2,000 chart accounts and 20 definitions per book."
    else super
    end
  end
  def unavailable
    return super if action_name.in?(%w[update retry completion])
    protected_feedback("Reports are temporarily unavailable. Test balances are not saved; report changes require explicit reviewed acceptance.", 503)
  end
end
