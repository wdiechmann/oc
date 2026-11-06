class JournalsController < FinanceSetupController
  def new
    show_setup
  end
  def history
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence })
    raise Ep::Client::Error.new(404, code: "not_found") unless data["selected"]
    content = Components::JournalHistory.new(data: data)
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end
  def posting_preview
    if params[:review_id].present?
      review = ep.journal_review(params[:tenant_id], params[:book_id], params[:review_id])
      preview, historical = review.dig("plan", "validation", "posting_preview"), true
    else
      data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence, version: params[:version].presence })
      unless data["selected"]
        raise Ep::Client::Error.new(404, code: "not_found") unless data["status"] == "pending"
        content = Components::SharedDialogFeedback.new(message: "The saved journal view is updating. Refresh the journal to view its posting preview.")
        return render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: :conflict
      end
      preview, historical = data.dig("selected", "validation", "posting_preview"), !!data["historical"]
    end
    content = Components::JournalPostingPreview.new(preview: preview, separator: decimal_separator, historical: historical, dialog: true)
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end
  def delete_dialog
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence })
    raise Ep::Client::Error.new(404, code: "not_found") unless data["selected"] && data.dig("permissions", "prepare")
    unless data["status"] == "ready"
      content = Components::SharedDialogFeedback.new(message: "The journal view is updating. Refresh the journal before deleting it.")
      return render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: :conflict
    end
    content = Components::JournalDeleteDialog.new(data: data, token: work_token("journal_delete", data["selected"]["id"]))
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end
  def details_dialog
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence })
    raise Ep::Client::Error.new(404, code: "not_found") unless data["selected"] && data.dig("permissions", "prepare")
    unless data["status"] == "ready"
      content = Components::SharedDialogFeedback.new(message: "The journal view is updating. Refresh the journal before editing its details.")
      return render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: :conflict
    end
    content = Components::JournalDetailsDialog.new(data: data, token: work_token("journal_details", data["selected"]["id"]))
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end
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

  def completion
    @attachment_row_id = session.dig(:finance_operation, "row_id")
    @action = session.dig(:finance_operation, "action")
    super
  end

  def accounts
    render json: ep.journal_accounts(params[:tenant_id], params[:book_id], params[:q].to_s)
  end
  def row_preview
    row = work_row_attributes
    render json: ep.journal_row_preview(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id], expected_draft_version: Integer(params[:expected_draft_version], exception: false), contexts: work_contexts, row: row })
  end
  def vat_operation
    row = work_row_attributes
    result = ep.journal_row_preview(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id], expected_draft_version: Integer(params[:expected_draft_version], exception: false), contexts: work_contexts, row: row })
    fields = params.permit(:row_id, :draft_id, :expected_draft_version, :expected_version, :reference, :amount, :credit_amount, :credit_override, :debit_account_id, :credit_account_id, :debit_label, :credit_label, :amount_basis, :basis_override, :vat_enabled, :vat_entry_id, :vat_source_side, :void, contexts: {}).to_h
    content = Components::JournalVatOperation.new(result: result, separator: decimal_separator, fields: fields, url: vat_operation_tenant_book_journals_path(params[:tenant_id], params[:book_id]), applied: params[:intent] == "apply_vat")
    updates = Components::JournalVatDraftStream.new(result: result, row_id: params[:row_id].presence || "new", separator: decimal_separator) if params[:intent] == "apply_vat"
    render Components::SharedDialogStream.new(content: content, updates: updates), content_type: "text/vnd.turbo-stream.html"
  end
  def attachments
    info = ep.journal_attachments(params[:tenant_id], params[:book_id], params[:row_id])
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: info.fetch("draft_id") })
    render_attachments(data, info)
  end
  def upload_attachment
    return pending_feedback if session[:finance_operation]
    file = params[:file]
    raise Ep::Client::Error.new(422, code: "invalid_attachment") unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.size.between?(1, 5_242_880)
    upload = ep.stage_journal_attachment(params[:tenant_id], params[:book_id], params[:row_id], { filename: file.original_filename, content_type: file.content_type, content: Base64.strict_encode64(file.read) })
    info = ep.journal_attachments(params[:tenant_id], params[:book_id], params[:row_id])
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: info.fetch("draft_id") })
    render_attachments(data, info, upload: upload)
  end
  def download_attachment
    file = ep.journal_attachment(params[:tenant_id], params[:book_id], params[:attachment_id])
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data Base64.strict_decode64(file.fetch("content")), filename: file.fetch("filename"), type: file.fetch("content_type"), disposition: "attachment"
  end

  private
  def accepted_notice(result)
    return "Journal deleted. Numbered postings and history are retained for traceability." if @action == "journal_delete"
    result["posting_id"] ? "Posting ID #{result['posting_id']} saved. The journal remains work in progress." : "Journal draft saved. Continue working on its lines."
  end
  def command_type(action) = action == "journal_save" ? "FinanceJournalDraft:save" : "FinanceJournalWork:#{work_mode(action)}"
  def execute_command(action, attrs, key)
    if action == "journal_attachment"
      @attachment_row_id ||= session.dig(:finance_operation, "row_id")
      session[:finance_operation]["row_id"] = @attachment_row_id if session[:finance_operation]
    end
    action == "journal_save" ? ep.accept_journal(params[:tenant_id], params[:book_id], attrs, key) : ep.journal_work(params[:tenant_id], params[:book_id], work_mode(action), attrs, key)
  end
  def destination(result = nil) = tenant_book_journals_path(params[:tenant_id], params[:book_id], draft_id: @action == "journal_delete" ? nil : result && result["draft_id"])
  def attributes_for(action, id)
    unless action == "journal_save"
      signed = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
      @decimal_separator = signed.fetch("decimal_separator")
      attrs = { expected_version: work_version(params[:expected_version]), contexts: work_contexts }
      attrs.merge!(draft_id: id, expected_draft_version: work_version(params[:expected_draft_version])) unless action == "journal_create"
      case action
      when "journal_create", "journal_details"
        attrs[:initial_row] = true if action == "journal_create"
        attrs[:data] = { name: params[:name].to_s, posting_date: params[:posting_date].to_s, reference: params[:reference].to_s }
        @work_header = attrs[:data].stringify_keys
        raise Ep::Client::Error.new(422, code: "invalid_journal") unless @work_header["name"].length <= 120 && @work_header["reference"].length <= 120 && @work_header["posting_date"].length <= 10
      when "journal_row"
        @work_draft = params.to_unsafe_h.slice("reference", "amount", "credit_amount", "credit_override", "debit_account_id", "credit_account_id", "debit_label", "credit_label", "amount_basis", "basis_override", "vat_enabled", "vat_entry_id", "vat_source_side", "void").merge("id"=>signed["row_id"])
        attrs[:row] = work_row_attributes(signed["row_id"])
        attrs[:append_row] = true if params[:intent] == "next_row"
      when "journal_delete"
        # The signed journal ID, versions and contexts govern audited deletion.
      when "journal_attachment"
        @attachment_row_id = signed.fetch("row_id")
        attrs[:upload_id] = signed.fetch("upload_id")
      else raise Ep::Client::Error.new(422, code: "invalid_journal")
      end
      return attrs
    end
    signed = Rails.application.message_verifier(:finance_setup).verified(params[:form_token].to_s, purpose: :finance_setup)
    raise Ep::Client::Error.new(422, code: "invalid_journal") unless action == "journal_save" && signed["digest"].present? && signed["expected_version"].is_a?(Integer)
    { review_id: id, digest: signed.fetch("digest"), expected_version: signed.fetch("expected_version") }
  end
  def show_setup(status: 200, message: nil)
    if request.format.turbo_stream? && @action == "journal_attachment" && @attachment_row_id
      info = ep.journal_attachments(params[:tenant_id], params[:book_id], @attachment_row_id)
      data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: info.fetch("draft_id") })
      return render_attachments(data, info, message: message, status: status)
    end
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: params[:draft_id].presence, version: params[:version].presence })
    review_id = params[:review_id].presence || @attrs && @attrs[:review_id]
    review = ep.journal_review(params[:tenant_id], params[:book_id], review_id) if review_id
    if review && params[:edit] == "1"
      @editing = review.fetch("plan").slice("draft_id", "expected_draft_version", "data", "contexts").merge("expected_version"=>review.fetch("expected_version"), "saved_validation"=>review.dig("plan", "validation"))
      review = nil
    end
    if !@editing && params[:edit] == "1" && data["selected"] && !(data["work_rows_enabled"] && data.dig("selected", "data", "rows"))
      @editing = { "draft_id"=>data["selected"]["id"], "expected_draft_version"=>data["selected"]["version"], "expected_version"=>data["latest_version"], "contexts"=>data["contexts"], "data"=>data["selected"]["data"], "saved_validation"=>data["selected"]["validation"] }
    end
    token = review_token(review) if review && !review["accepted_command_id"] && data.dig("permissions", "prepare") && data["status"] == "ready" && !session[:finance_operation]
    creation = action_name == "new" || @action == "journal_create"
    unless creation || params[:draft_id].present? || review_id || @editing || @work_draft || @work_header
      return render Views::Journals::Index.new(data: data, message: message, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
    data = data.merge("selected"=>nil, "historical"=>false) if creation
    if @action == "journal_details" && @work_header && message && data["selected"] && data.dig("permissions", "prepare") && data["status"] == "ready" && !session[:finance_operation]
      dialog = Components::JournalDetailsDialog.new(data: data, token: work_token("journal_details", data["selected"]["id"]), values: @work_header, message: message)
    end
    render Views::Journals::Show.new(dialog: dialog, new_journal: creation, requested_id: params[:draft_id], requested_version: params[:version], work_token: method(:work_token), work_draft: @work_draft, work_header: @work_header, decimal_separator: decimal_separator, data: data, review: review, token: token, editing: @editing, extra_line: @extra_line, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, notice: flash[:notice]), status: status
  end
  def feedback(message, status:)
    return super unless request.format.turbo_stream? && @action == "journal_attachment"
    content = Components::SharedDialogFeedback.new(message: message, check_url: completion_url, retry_url: retry_url)
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: status
  end
  def respond_accepted(result, notice:)
    return super unless request.format.turbo_stream? && @action == "journal_attachment" && @attachment_row_id
    info = ep.journal_attachments(params[:tenant_id], params[:book_id], @attachment_row_id)
    data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: result.fetch("draft_id") })
    render_attachments(data, info, refresh: true, message: notice)
  end
  def render_attachments(data, info, upload: nil, refresh: false, message: nil, status: 200)
    if request.format.turbo_stream?
      content = Components::JournalAttachments.new(data: data, info: info, upload: upload, token: method(:work_token), message: message, check_url: completion_url, retry_url: retry_url)
      journal = refresh ? Views::Journals::Show.new(fragment: true, work_token: method(:work_token), decimal_separator: decimal_separator, data: data, signed_in: signed_in?) : nil
      render Components::SharedDialogStream.new(content: content, journal: journal), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Journals::Attachments.new(data: data, info: info, upload: upload, token: method(:work_token), signed_in: signed_in?), status: status
    end
  end
  def decimal_separator = @decimal_separator || JournalMoney.separator(request.headers["Accept-Language"])
  def work_mode(action) = { "journal_create"=>"create", "journal_row"=>"row", "journal_attachment"=>"attachment", "journal_details"=>"details", "journal_delete"=>"delete" }.fetch(action)
  def work_token(action, draft_id = nil, row_id = nil, upload = nil)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>action, "account_id"=>draft_id, "row_id"=>row_id, "upload_id"=>upload && upload["upload_id"], "decimal_separator"=>decimal_separator, "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 4.hours)
  end
  def work_version(value)
    text = value.to_s
    text.match?(/\A\d{1,19}\z/) ? text.to_i : nil
  end
  def work_contexts
    raise Ep::Client::Error.new(422, code: "invalid_journal") unless params[:contexts].is_a?(ActionController::Parameters)
    currency, authority = params.dig(:contexts, :base_currency).to_s, params.dig(:contexts, :accounting_authority).to_s
    raise Ep::Client::Error.new(422, code: "invalid_journal") if currency.length > 3 || authority.length > 20
    %w[setup_version period_version book_version].to_h { |k| [ k, work_version(params.dig(:contexts, k)) ] }.merge("base_currency"=>currency, "accounting_authority"=>authority)
  end
  def work_row_attributes(id = params[:row_id].presence)
    raise Ep::Client::Error.new(422, code: "invalid_journal") if params[:reference].to_s.length > 120
    [ params[:debit_account_id].presence, params[:credit_account_id].presence, id ].compact.each do |value|
      raise Ep::Client::Error.new(422, code: "invalid_account_reference") unless value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
    end
    %w[debit credit].each do |side|
      raise Ep::Client::Error.new(422, code: "invalid_account_reference") if params["#{side}_label"].present? && params["#{side}_account_id"].blank?
    end
    minor = JournalMoney.parse(params[:amount], separator: decimal_separator, signed: true)
    raise Ep::Client::Error.new(422, code: "invalid_amount") if minor.nil?
    credit = params[:credit_override] == "true" ? JournalMoney.parse(params[:credit_amount], separator: decimal_separator, signed: true) : nil
    raise Ep::Client::Error.new(422, code: "invalid_amount") if params[:credit_override] == "true" && credit.nil?
    attrs = { credit_amount_minor: credit, id: id, reference: params[:reference].to_s, debit_account_id: params[:debit_account_id].presence, credit_account_id: params[:credit_account_id].presence, amount_minor: minor, amount_basis: params[:amount_basis].presence, basis_override: params.key?(:basis_override) ? params[:basis_override] == "true" : params[:amount_basis].present?, void: params[:void] == "true" }
    if params.key?(:vat_enabled)
      raise Ep::Client::Error.new(422, code: "invalid_journal") unless %w[true false].include?(params[:vat_enabled])
      attrs[:vat_enabled] = params[:vat_enabled] == "true"
    end
    if params.key?(:vat_entry_id)
      entry = params[:vat_entry_id].presence
      raise Ep::Client::Error.new(422, code: "invalid_vat_reference") if entry && (!entry.is_a?(String) || !entry.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) || !%w[debit credit].include?(params[:vat_source_side]))
      attrs[:vat_entry_id] = entry
      attrs[:vat_source_side] = entry && params[:vat_source_side]
    end
    attrs
  end
  def review_token(review)
    session[:finance_form_nonce] ||= SecureRandom.hex(16)
    Rails.application.message_verifier(:finance_setup).generate({ "scope"=>form_scope, "nonce"=>session[:finance_form_nonce], "action"=>"journal_save", "account_id"=>review.fetch("review_id"), "digest"=>review.fetch("digest"), "expected_version"=>review.fetch("expected_version"), "key"=>SecureRandom.uuid }, purpose: :finance_setup, expires_in: 1.hour)
  end
  def setup_error(error)
    if request.format.turbo_stream? && action_name == "upload_attachment" && [ 409, 422 ].include?(error.status)
      info = ep.journal_attachments(params[:tenant_id], params[:book_id], params[:row_id])
      data = ep.journals(params[:tenant_id], params[:book_id], { draft_id: info.fetch("draft_id") })
      return render_attachments(data, info, message: error_message(error.code), status: error.status)
    end
    if action_name.in?(%w[accounts row_preview])
      reset_session if error.status == 401
      return render json: { error: error.code }, status: error.status
    end
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
    when "invalid_attachment" then "Choose a PDF, PNG or JPEG file up to 5 MiB with a simple filename."
    when "numbered_row_cannot_disappear" then "Numbered rows remain in the audit trail. Void the row instead of removing it."
    when "invalid_journal"
      return "Check the draft name/date, account choices and whether the amount includes VAT." if @action.to_s.start_with?("journal_") && @action != "journal_save"
      "Check the name, date, references and lines. Use whole minor units; optional VAT bases require an explicitly selected VAT entry."
    when "invalid_amount"
      return "Enter a signed amount with #{decimal_separator} as decimal point, at most two decimals and no thousands separators." if @action == "journal_row"
      "Debit and credit must be nonnegative whole minor units, up to 9,000,000,000,000 per line. VAT bases and assessed amounts may be signed."
    when "invalid_account_reference", "invalid_vat_reference" then "Choose accounts and VAT entries from this book. Unavailable saved choices are retained for comparison."
    when "view_pending" then "A journal, setup or period view is updating. Refresh before reviewing."
    when "review_expired" then "This private review expired. Review the journal again before saving."
    when "journal_limit" then "A book supports up to 100 journal drafts, each with up to 100 lines."
    else super
    end
  end
  def unavailable
    return render(json: { error: "unavailable" }, status: 503) if action_name.in?(%w[accounts row_preview])
    return super if action_name.in?(%w[update retry completion])
    protected_feedback("Journal drafts are temporarily unavailable. Changes require explicit reviewed draft acceptance.", 503)
  end
end
