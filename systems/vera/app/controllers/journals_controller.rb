class JournalsController < FinanceSetupController
  def review
    return pending_feedback if session[:finance_operation]
    raw = params[:lines]
    raise Ep::Client::Error.new(422, code: "invalid_journal") unless raw.is_a?(ActionController::Parameters) && raw.keys.length <= 100 && raw.each_pair.all? { |_, l| l.is_a?(ActionController::Parameters) }
    lines = raw.each_pair.reject { |_, l| l[:remove] == "1" }.map do |_, l|
      %w[id account_id reference debit_minor credit_minor vat_entry_id net_minor assessed_vat_minor].to_h { |key| [ key, l[key].to_s ] }
    end.reject { |l| l["id"].blank? && l["account_id"].blank? && l["reference"].blank? && l["vat_entry_id"].blank? && %w[debit_minor credit_minor net_minor assessed_vat_minor].all? { |key| l[key].blank? || l[key] == "0" } }
    raise Ep::Client::Error.new(422, code: "invalid_journal") unless params[:contexts].is_a?(ActionController::Parameters)
    @editing = { "draft_id"=>params[:draft_id].presence, "expected_draft_version"=>Integer(params[:expected_draft_version], exception: false), "expected_version"=>Integer(params[:expected_version], exception: false),
      "contexts"=>%w[setup_version period_version book_version].to_h { |key| [ key, Integer(params.dig(:contexts, key), exception: false) ] }.merge("base_currency"=>params.dig(:contexts, :base_currency).to_s, "accounting_authority"=>params.dig(:contexts, :accounting_authority).to_s),
      "data"=>{ "name"=>params[:name].to_s, "posting_date"=>params[:posting_date].to_s, "reference"=>params[:reference].to_s, "lines"=>lines } }
    if params[:intent] == "add_line"
      @extra_line = true
      return show_setup
    end
    body = @editing.deep_dup
    body["data"]["lines"].each do |line|
      %w[id account_id vat_entry_id].each { |key| line[key] = line[key].presence }
      %w[debit_minor credit_minor].each { |key| line[key] = line[key].blank? ? 0 : Integer(line[key], exception: false) }
      %w[net_minor assessed_vat_minor].each { |key| line[key] = line[key].blank? ? nil : Integer(line[key], exception: false) }
    end
    result = ep.review_journal(params[:tenant_id], params[:book_id], body)
    redirect_to tenant_book_journals_path(params[:tenant_id], params[:book_id], review_id: result.fetch("review_id")), status: :see_other
  end

  private
  def accepted_notice(result) = "Journal draft saved at revision #{result.fetch('stream_version')}. It remains unposted."
  def command_type(_action) = "FinanceJournalDraft:save"
  def execute_command(_action, attrs, key) = ep.accept_journal(params[:tenant_id], params[:book_id], attrs, key)
  def destination(result = nil) = tenant_book_journals_path(params[:tenant_id], params[:book_id], draft_id: result && result["draft_id"])
  def attributes_for(action, id)
    signed = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    raise Ep::Client::Error.new(422, code: "invalid_journal") unless action == "journal_save" && signed["digest"].present? && signed["expected_version"].is_a?(Integer)
    { review_id: id, digest: signed.fetch("digest"), expected_version: signed.fetch("expected_version") }
  end
  def show_setup(status: 200, message: nil)
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence, version: params[:version].presence })
    review_id = params[:review_id].presence || @attrs && @attrs[:review_id]
    review = ep.journal_review(params[:tenant_id], params[:book_id], review_id) if review_id
    if review && params[:edit] == "1"
      @editing = review.fetch("plan").slice("draft_id", "expected_draft_version", "data", "contexts").merge("expected_version"=>review.fetch("expected_version"), "saved_validation"=>review.dig("plan", "validation"))
      review = nil
    end
    if !@editing && params[:edit] == "1" && data["selected"]
      @editing = { "draft_id"=>data["selected"]["id"], "expected_draft_version"=>data["selected"]["version"], "expected_version"=>data["latest_version"], "contexts"=>data["contexts"], "data"=>data["selected"]["data"], "saved_validation"=>data["selected"]["validation"] }
    end
    token = review_token(review) if review && !review["accepted_command_id"] && data.dig("permissions", "prepare") && data["status"] == "ready" && !session[:finance_operation]
    render Views::Journals::Show.new(data: data, review: review, token: token, editing: @editing, extra_line: @extra_line, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, notice: flash[:notice]), status: status
  end
  def review_token(review)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>"journal_save", "account_id"=>review.fetch("review_id"), "digest"=>review.fetch("digest"), "expected_version"=>review.fetch("expected_version"), "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 1.hour)
  end
  def setup_error(error)
    if error.code == "review_expired"
      session.delete(:finance_operation)
      return protected_feedback(error_message(error.code), 410)
    end
    return super if [ 401, 403, 404 ].include?(error.status) || error.code == "idempotency_conflict" || action_name.in?(%w[update retry completion])
    return unavailable if error.status >= 500
    if @editing && error.code == "version_conflict"
      current = ep.journals(params[:tenant_id], params[:book_id], { draft_id: @editing["draft_id"] }.compact)
      @editing.merge!("expected_version"=>current["latest_version"], "expected_draft_version"=>current.dig("selected", "version"), "contexts"=>current["contexts"])
    end
    show_setup(status: error.status, message: error_message(error.code))
  end
  def error_message(code)
    case code
    when "version_conflict" then "The journal, chart, VAT rules, book or periods changed. Compare your draft with the current saved version and review again explicitly."
    when "invalid_journal" then "Check the name, date, references and lines. Use whole minor units; optional VAT bases require an explicitly selected VAT entry."
    when "invalid_amount" then "Debit and credit must be nonnegative whole minor units, up to 9,000,000,000,000 per line. VAT bases and assessed amounts may be signed."
    when "invalid_account_reference", "invalid_vat_reference" then "Choose accounts and VAT entries from this book. Unavailable saved choices are retained for comparison."
    when "view_pending" then "A journal, setup or period view is updating. Refresh before reviewing."
    when "review_expired" then "This private review expired. Review the journal again before saving."
    when "journal_limit" then "A book supports up to 100 journal drafts, each with up to 100 lines."
    else super
    end
  end
  def unavailable
    return super if action_name.in?(%w[update retry completion])
    protected_feedback("Journal drafts are temporarily unavailable. Changes require explicit reviewed draft acceptance.", 503)
  end
end
