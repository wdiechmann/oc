class VatRulesController < FinanceSetupController
  private
  def destination(_result = nil) = tenant_book_vat_rules_path(params[:tenant_id], params[:book_id])
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
    if params[:preset_id].present? && !@attrs
      preset = Array(data["presets"]).find { |p| p["id"] == params[:preset_id] && (params[:preset_version].blank? || p["version"] == params[:preset_version]) }
      if preset
        aliases = preset.fetch("aliases").map(&:downcase)
        matches = data.fetch("vat_entries").select { |e| e["active"] && aliases.include?(e["code"].split(/\s+[-–]\s+/, 2).first.strip.downcase) }
        @action = "vat_rule_create"
        @attrs = preset.slice("direction", "rate_bps", "deductible_bps", "mappings", "assessment_basis").symbolize_keys.merge(preset_id: preset.fetch("id"), preset_version: preset.fetch("version"), vat_entry_id: matches.one? ? matches.first.fetch("id") : nil)
      else
        status, message = 422, "That preset version is unavailable. Select a current Danish preset."
      end
    end
    render Views::VatRules::Show.new(data: data, token: method(:form_token), draft: @attrs && { action: @action, attrs: @attrs }, message: message, check_url: completion_url, retry_url: retry_url, signed_in: signed_in?, notice: flash[:notice]), status: status
  end
  def error_message(code)
    case code
    when "invalid_vat_posting_account" then "Choose active posting accounts from this book for VAT and non-deductible amounts."
    when "invalid_vat_preset" then "That preset reference is unavailable. Select a current preset; existing rule history is preserved."
    when "vat_rule_overlap" then "Active date ranges for this VAT entry overlap. End the earlier rule before the next rule begins."
    when "invalid_vat_rule" then "Check dates, percentages (0–100, up to two decimals), direction and reporting mappings. Output rules have no deductible share; no-VAT rules use zero percentages. Other rules need at least one reporting box. Import-statement assessment requires reverse charge."
    when "invalid_vat_reference" then "Select a VAT entry from this book. A rule cannot move to another entry."
    when "inactive_catalogue_entry" then "Create new rules only for active VAT entries."
    when "version_conflict" then "A newer setup/rule revision exists. Your draft is preserved; compare it with the accepted rule before reapplying."
    when "catalogue_not_initialized" then "Initialize the book’s catalogues before adding VAT rules."
    else super
    end
  end
end
