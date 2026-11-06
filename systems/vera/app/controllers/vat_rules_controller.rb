class VatRulesController < FinanceSetupController
  def refresh_row
    ticket = Rails.application.message_verifier(:vat_row_refresh).verified(params[:ticket].to_s, purpose: :vat_row_refresh)
    unless ticket && ticket["scope"] == form_scope
      return protected_feedback("Refresh the VAT index to check the updated settings.", 422)
    end
    data = ep.vat_rules(params[:tenant_id], params[:book_id])
    render Components::VatRowRefreshStream.new(data: data, entry_id: ticket.fetch("entry_id"), as_of: Date.iso8601(ticket.fetch("as_of")), version: ticket.fetch("version"), refresh_url: request.fullpath, token: method(:form_token)), content_type: "text/vnd.turbo-stream.html"
  end
  private
  def destination(_result = nil)
    entry=@attrs && (@attrs[:vat_entry_id] || @attrs["vat_entry_id"])
    tenant_book_vat_rules_path(params[:tenant_id], params[:book_id], vat_entry_id: entry, anchor: entry && "vat-code-#{entry}")
  end
  def execute_command(action, attrs, key) = ep.vat_rule_command(params[:tenant_id], params[:book_id], action.delete_prefix("vat_rule_"), attrs, key)
  def attributes_for(action, rule_id)
    raise Ep::Client::Error.new(422, code: "invalid_vat_rule") unless %w[vat_rule_create vat_rule_revise].include?(action)
    mappings = Array(params[:mappings]).map { |m| { box: m[:box].to_s, component: m[:component].to_s, sign: Integer(m[:sign], exception: false) } }.reject { |m| m[:box].blank? }
    attrs = { expected_version: Integer(params[:expected_version], exception: false), vat_entry_id: params[:vat_entry_id].to_s, valid_from: params[:valid_from].to_s, valid_until: params[:valid_until].presence, direction: params[:direction].to_s, rate_bps: percentage(params[:rate]), deductible_bps: percentage(params[:deductible]), mappings: mappings }
    if params.key?(:posting_accounts)
      selected=params[:posting_accounts]
      valid=selected.is_a?(ActionController::Parameters) && (selected.keys-%w[input output non_deductible]).empty? && selected.values.all? { |id| id.blank? || (id.is_a?(String) && id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)) }
      raise Ep::Client::Error.new(422, code: "invalid_vat_posting_account") unless valid
      attrs[:posting_accounts] = %w[input output non_deductible].to_h { |role| [ role, selected[role].presence ] }
    end
    attrs[:assessment_basis] = params[:assessment_basis].to_s if params.key?(:assessment_basis)
    if params.key?(:preset_id) || params.key?(:preset_version)
      attrs.merge!(preset_id: params[:preset_id].to_s, preset_version: params[:preset_version].to_s)
    end
    attrs.merge!(rule_id: rule_id, expected_rule_version: Integer(params[:expected_rule_version], exception: false), active: params[:active] == "true") if action == "vat_rule_revise"
    attrs
  end
  def percentage(value)
    match = /\A(\d{1,3})(?:\.(\d{1,2}))?\z/.match(value.to_s)
    match && match[1].to_i * 100 + match[2].to_s.ljust(2, "0").to_i
  end
  def show_setup(status: 200, message: nil)
    data = ep.vat_rules(params[:tenant_id], params[:book_id])
    selected=params[:vat_entry_id].presence || (@attrs && @attrs[:vat_entry_id])
    if selected && !data.fetch("vat_entries").any? { |entry| entry["id"]==selected }
      raise Ep::Client::Error.new(404, code: "invalid_vat_reference")
    end
    as_of=Time.current.in_time_zone("Europe/Copenhagen").to_date
    if params[:as_of].present?
      parsed=Date.iso8601(params[:as_of].to_s) rescue nil
      if parsed && parsed.iso8601==params[:as_of]
        as_of=parsed
      else
        status, message=422, "Choose a valid settings date."
      end
    end
    if params[:preset_id].present? && !@attrs
      preset = Array(data["presets"]).find { |p| p["id"] == params[:preset_id] && (params[:preset_version].blank? || p["version"] == params[:preset_version]) }
      if preset
        aliases = preset.fetch("aliases").map(&:downcase)
        matches = data.fetch("vat_entries").select { |e| e["active"] && aliases.include?(e["code"].split(/\s+[-–]\s+/, 2).first.strip.downcase) }
        @action = "vat_rule_create"
        @attrs = preset.slice("direction", "rate_bps", "deductible_bps", "mappings", "assessment_basis").symbolize_keys.merge(preset_id: preset.fetch("id"), preset_version: preset.fetch("version"), vat_entry_id: selected || (matches.one? ? matches.first.fetch("id") : nil))
      else
        status, message = 422, "That preset version is unavailable. Select a current Danish preset."
      end
    end
    source_id = params[:change_from].presence || params[:copy_from].presence
    if !@attrs && source_id
      source=data.fetch("vat_rules").find { |rule| rule["id"]==source_id && (!selected || rule["vat_entry_id"]==selected) }
      if source
        selected=source.fetch("vat_entry_id")
        @action="vat_rule_create"
        @attrs=source.slice("vat_entry_id", "direction", "rate_bps", "deductible_bps", "assessment_basis", "posting_accounts").symbolize_keys.merge(mappings: source.dig("mappings", "lines"))
        @attrs.merge!(preset_id: source["preset"]["id"], preset_version: source["preset"]["version"]) if source["preset"]
      else
        status, message=422, "Choose existing settings from this VAT code to prepare a change."
      end
    end
    selected ||= @attrs && @attrs[:vat_entry_id]
    options = { data: data, token: method(:form_token), draft: @attrs && { action: @action, attrs: @attrs }, selected_entry: selected, as_of: as_of, message: message, check_url: completion_url, retry_url: retry_url }
    if request.format.turbo_stream? && selected
      display_data = @refresh_version && data["source_version"].to_i < @refresh_version ? data.merge("status"=>"pending") : data
      content = Views::VatRules::Detail.new(**options.merge(data: display_data))
      if @refresh_version
        ticket = Rails.application.message_verifier(:vat_row_refresh).generate({ scope: form_scope, entry_id: selected, as_of: as_of.iso8601, version: @refresh_version }, purpose: :vat_row_refresh, expires_in: 1.hour)
        url = refresh_row_tenant_book_vat_rules_path(params[:tenant_id], params[:book_id], ticket: ticket)
        updates = Components::VatRowRefreshStream.new(data: data, entry_id: selected, as_of: as_of, version: @refresh_version, refresh_url: url, token: method(:form_token))
      end
      render Components::SharedDialogStream.new(content: content, updates: updates), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::VatRules::Show.new(**options, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
  end
  def respond_accepted(result, notice:)
    return super unless request.format.turbo_stream?
    params[:vat_entry_id] = @attrs[:vat_entry_id]
    @attrs = nil
    @refresh_version = result.fetch("stream_version").to_i
    show_setup(message: notice)
  end
  def feedback(message, status:)
    return super unless request.format.turbo_stream?
    content = Components::SharedDialogFeedback.new(message: message, check_url: completion_url, retry_url: retry_url)
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: status
  end
  def error_message(code)
    case code
    when "invalid_vat_posting_account" then "Choose active posting accounts from this book for VAT and non-deductible amounts."
    when "invalid_vat_preset" then "That preset reference is unavailable. Select a current preset; existing rule history is preserved."
    when "vat_rule_overlap" then "Active date ranges for this VAT code overlap. End the current settings the day before the new settings start."
    when "invalid_vat_rule" then "Check dates, percentages (0–100, up to two decimals), direction and reporting mappings. Output VAT uses no deductible share; no-VAT settings use zero percentages. Other settings need VAT-return reporting from a preset or Advanced. Import-statement assessment requires reverse charge."
    when "invalid_vat_reference" then "Select a VAT code from this book. Saved settings cannot move to a different code."
    when "inactive_catalogue_entry" then "Create new dated settings only for active VAT codes."
    when "version_conflict" then "A newer version of the VAT code settings exists. Your draft is preserved; compare it with the accepted rule before reapplying."
    when "catalogue_not_initialized" then "Initialize the book’s catalogues before adding VAT rules."
    else super
    end
  end
end
