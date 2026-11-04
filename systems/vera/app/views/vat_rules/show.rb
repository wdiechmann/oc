class Views::VatRules::Show < Views::Base
  def initialize(data:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil, **options)
    super(**options)
    @data, @token, @draft, @message, @check, @retry = data, token, draft, message, check_url, retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data["catalogues_initialized"] && data.dig("permissions", "configure") && !check_url
  end
  def view_template
    div(id: "vera-book-content", class: "break-words") do
      a(href: tenant_book_catalogues_path(@tid, @bid), class: "text-teal-900 underline") { "← VAT and category catalogues" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      h1(class: "mt-2 text-3xl font-semibold") { "Effective VAT rules" }
      p(class: "mt-4 text-sm text-stone-600") { "Choose a Danish preset or configure each VAT entry manually. Dates are inclusive; an empty end date means ongoing. Rates and reporting boxes are entered by the book’s steward. Imported labels do not imply a rate or a legal treatment." }
      p(class: "mt-3 text-sm text-stone-600") { "Input VAT may be partly deductible. Reverse charge assesses VAT without adding it to the invoice total. Reporting mappings choose which net/VAT amounts contribute to each box, with a positive or negative sign." }
      p(role: "alert", class: "mt-4 rounded-lg bg-amber-50 p-4") { @message } if @message
      p(class: "mt-4 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      a(href: tenant_book_vat_rules_path(@tid, @bid), class: "mt-3 block text-sm text-teal-900 underline") { "Refresh rules" }
      if @check
        a(href: @check, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      p(role: "status", class: "mt-4 rounded-lg bg-amber-50 p-4") { "The rule view is updating. Refresh before saving another change." } unless @data["status"] == "ready"
      if @draft && !@editable
        pre(class: "mt-4 whitespace-pre-wrap rounded-lg bg-amber-50 p-4 text-sm") { @draft[:attrs].to_json }
      end
      presets
      @data.fetch("vat_rules").each do |rule|
        section(id: "vat-rule-#{rule['id']}", class: "mt-6 rounded-xl border border-stone-200 bg-white p-5") do
          entry = @data.fetch("vat_entries").find { |e| e["id"] == rule["vat_entry_id"] }
          h2(class: "text-lg font-semibold") { entry ? "#{entry['code']} · #{entry['name']}" : rule["vat_entry_id"] }
          p(class: "mt-2 text-sm") { "#{rule['valid_from']} → #{rule['valid_until'] || 'Ongoing'} · #{rule['direction']} · VAT #{percent(rule['rate_bps'])}% · Deductible #{percent(rule['deductible_bps'])}% · #{rule['active'] ? 'Active' : 'Inactive'}" }
          p(class: "mt-2 text-sm text-amber-900") { "This VAT entry is inactive; its rules are retained for history." } if entry && !entry["active"]
          preset_details(rule["preset"])
          p(class: "mt-2 text-sm font-medium") { "VAT amount comes from the import statement; supplier net does not determine the assessment." } if rule["assessment_basis"] == "import_statement"
          mapping_lines(rule.fetch("mappings").fetch("lines"))
          rule_form(rule) if @editable && @draft && @draft.dig(:attrs, :rule_id) == rule["id"]
          if @editable && !(@draft && @draft.dig(:attrs, :rule_id) == rule["id"])
            details(class: "mt-4") { summary(class: "cursor-pointer text-sm text-teal-900") { "Edit rule" }; rule_form(rule) }
          end
          details(class: "mt-4 border-t pt-3") do
            summary(class: "cursor-pointer text-sm text-teal-900") { "Rule history (#{rule.fetch('history', []).length})" }
            rule.fetch("history", []).reverse_each do |h|
              p(class: "mt-3 text-sm") { "#{h['valid_from']} → #{h['valid_until'] || 'Ongoing'} · #{h['direction']} · VAT #{percent(h['rate_bps'])}% · Deductible #{percent(h['deductible_bps'])}% · #{h['active'] ? 'Active' : 'Inactive'} · Revision #{h['version']}" }
              preset_details(h["preset"])
              mapping_lines(h.fetch("mappings").fetch("lines"))
              p(class: "mt-1 text-xs text-stone-500") { "#{h['accepted_at']} · Actor #{h['actor_identity_id']} · Application #{h['application_id']}" }
            end
          end
        end
      end
      if @editable
        h2(class: "mt-8 text-xl font-semibold") { "Add a dated rule" }
        rule_form(nil)
      end
    end
  end
  def presets
    items = Array(@data["presets"])
    return if items.empty?
    details(class: "mt-6 rounded-xl border border-stone-200 bg-white p-4", id: "danish-vat-presets") do
      summary(class: "cursor-pointer font-semibold text-teal-900") { "Danish VAT presets (#{items.length})" }
      p(class: "mt-3 text-sm text-stone-600") { "Templates for reviewed setup. The source-check date is not an effective start date. Deduction assumes eligible business use; adjust for mixed or private use. EU sales-list reporting is separate from VAT-return boxes." }
      items.each do |preset|
        section(class: "mt-4 rounded-lg border border-stone-200 p-4", id: "preset-#{preset['id']}") do
          h2(class: "font-semibold") { "#{preset['id']} · #{preset['title']}" }
          p(class: "mt-2 text-sm") { "#{preset['direction']} · VAT #{percent(preset['rate_bps'])}% · Deductible #{percent(preset['deductible_bps'])}%" }
          mapping_lines(preset.fetch("mappings"))
          preset_details(preset)
          a(href: tenant_book_vat_rules_path(@tid, @bid, preset_id: preset.fetch("id"), preset_version: preset.fetch("version"), anchor: "vat_rule_create-new"), class: "mt-3 inline-block text-sm font-semibold text-teal-900 underline") { "Use #{preset['id']} preset" } if @editable
        end
      end
    end
  end
  def preset_details(preset)
    return unless preset
    div(class: "mt-3 rounded-lg bg-teal-50 p-3 text-sm") do
      p(class: "font-medium") { "Based on #{preset['id']} · Version #{preset['version']} · Sources checked #{preset['checked_on']}#{preset['customized'] ? ' · Customized values' : ''}" }
      p(class: "mt-2") { preset["conditions"] }
      Array(preset["sources"]).each_with_index { |url, i| a(href: url, target: "_blank", rel: "noopener noreferrer", class: "mt-2 mr-4 inline-block text-teal-900 underline") { "Source #{i + 1}" } }
    end
  end
  def percent(bps)
    return "" if bps.nil?
    whole, fraction = bps.to_i.divmod(100)
    "#{whole}.#{fraction.to_s.rjust(2, '0')}"
  end
  def mapping_lines(lines)
    p(class: "mt-2 text-xs text-stone-500") { "No reporting boxes configured." } if lines.empty?
    lines.each { |m| p(class: "mt-2 text-xs text-stone-600") { "#{m['box']}: #{m['sign'] == -1 ? '−' : '+'} #{m['component'].tr('_', ' ')}" } }
  end
  def rule_form(rule)
    action = rule ? "vat_rule_revise" : "vat_rule_create"
    draft = @draft && @draft[:action] == action && @draft.dig(:attrs, :rule_id) == (rule && rule["id"]) ? @draft[:attrs].deep_stringify_keys : nil
    values = draft || rule || {}
    mappings = draft ? values["mappings"] : values.dig("mappings", "lines") || []
    form_with(url: tenant_book_vat_rules_path(@tid, @bid), method: :patch, namespace: rule ? rule["id"] : "new-rule", id: "#{action}-#{rule && rule['id'] || 'new'}", class: "mt-4 rounded-lg border border-stone-200 bg-white p-4", data: { turbo: false }) do |f|
      p(class: "mb-3 font-medium text-amber-900") { values["preset_id"] ? "Preset draft — review the entry, dates, amounts and usage conditions before saving." : "Your draft — compare with the accepted rule above" } if draft
      origin = values["preset"] || Array(@data["presets"]).find { |p| p["id"] == values["preset_id"] && p["version"] == values["preset_version"] }
      if origin
        f.hidden_field(:preset_id, value: origin.fetch("id"))
        f.hidden_field(:preset_version, value: origin.fetch("version"))
        preset_details(origin)
      end
      f.hidden_field(:form_token, value: @token.call(action, rule && rule["id"]))
      f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
      f.hidden_field(:expected_rule_version, value: rule["version"]) if rule
      div(class: "grid gap-4 sm:grid-cols-2 lg:grid-cols-3") do
        div do
          f.label(:vat_entry_id, "VAT entry")
          choices = @data.fetch("vat_entries").select { |e| e["active"] || e["id"] == values["vat_entry_id"] }.map { |e| [ "#{e['code']} · #{e['name']}", e["id"] ] }
          f.select(:vat_entry_id, choices, { selected: values["vat_entry_id"], include_blank: "Choose VAT entry" }, class: FIELD, required: true, disabled: !!rule)
          f.hidden_field(:vat_entry_id, value: values["vat_entry_id"]) if rule
        end
        %w[valid_from valid_until].each do |field|
          div { f.label(field, field == "valid_from" ? "Valid from" : "Valid until (optional)"); f.date_field(field, value: values[field], required: field == "valid_from", class: FIELD) }
        end
        div { f.label(:direction, "Treatment"); f.select(:direction, [ [ "Input VAT", "input" ], [ "Output VAT", "output" ], [ "Reverse charge", "reverse_charge" ], [ "No VAT", "none" ] ], { selected: values["direction"], include_blank: "Choose treatment" }, class: FIELD, required: true) }
        div { f.label(:assessment_basis, "VAT assessment"); f.select(:assessment_basis, [ [ "Calculate from net base", "net" ], [ "Import statement amount", "import_statement" ] ], { selected: values["assessment_basis"] || "net" }, class: FIELD) }
        div { f.label(:rate, "VAT rate (%)"); f.number_field(:rate, value: percent(values["rate_bps"]), step: "0.01", min: 0, max: 100, required: true, class: FIELD) }
        div { f.label(:deductible, "Deductible VAT share (%)"); f.number_field(:deductible, value: percent(values["deductible_bps"]), step: "0.01", min: 0, max: 100, required: true, class: FIELD) }
        div { f.label(:active, "Status"); f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: values["active"].to_s }, class: FIELD) } if rule
      end
      p(class: "mt-4 text-sm font-medium") { "Reporting mappings (up to four; leave unused boxes blank)" }
      4.times do |i|
        m = mappings[i] || {}
        div(class: "mt-3 grid gap-3 sm:grid-cols-3") do
          div { label { "Reporting box" }; input(name: "mappings[][box]", value: m["box"], maxlength: 60, aria_label: "Reporting box #{i+1}", class: FIELD) }
          div do
            label { "Amount component" }
            select(name: "mappings[][component]", aria_label: "Amount component #{i+1}", class: FIELD) { option(value: "", selected: m["component"].blank?) { "Choose amount" }; [ [ "Net base", "net" ], [ "Assessed VAT", "vat" ], [ "Deductible VAT", "deductible_vat" ], [ "Non-deductible VAT", "non_deductible_vat" ] ].each { |label, value| option(value: value, selected: m["component"] == value) { label } } }
          end
          div { label { "Sign" }; select(name: "mappings[][sign]", aria_label: "Sign #{i+1}", class: FIELD) { option(value: "1", selected: m["sign"] != -1) { "+ Add" }; option(value: "-1", selected: m["sign"] == -1) { "− Subtract" } } }
        end
      end
      f.submit(draft && (@message || !values["preset_id"]) ? "Reapply rule draft" : rule ? "Save rule" : "Create dated rule", class: BUTTON)
    end
  end
end
