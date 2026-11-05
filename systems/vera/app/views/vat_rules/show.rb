class Views::VatRules::Show < Views::Base
  def initialize(data:, token:, draft: nil, selected_entry: nil, as_of: nil, message: nil, check_url: nil, retry_url: nil, **options)
    super(**options)
    @data, @token, @draft, @message, @check, @retry = data, token, draft, message, check_url, retry_url
    @selected_entry, @as_of=selected_entry, (as_of || Time.current.in_time_zone("Europe/Copenhagen").to_date)
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data["catalogues_initialized"] && data.dig("permissions", "configure") && !check_url
  end
  def view_template
    div(id: "vera-book-content", class: "break-words") do
      a(href: tenant_book_catalogues_path(@tid, @bid), class: "text-teal-900 underline") { "← VAT code names and categories" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      h1(class: "mt-2 text-3xl font-semibold") { "VAT codes" }
      p(class: "mt-4 text-sm text-stone-600") { "These are the same VAT codes selected on your chart-of-accounts accounts. Each code has dated settings for rates, deduction and VAT accounts; the journal uses the settings valid on its posting date." }
      p(class: "mt-3 text-sm text-stone-600") { "Keep using the same code when VAT changes. Schedule new dated settings under that code; saved earlier postings and previews keep their original configuration." }
      p(role: "alert", class: "mt-4 rounded-lg bg-amber-50 p-4") { @message } if @message
      p(class: "mt-4 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      a(href: tenant_book_vat_rules_path(@tid, @bid), class: "mt-3 block text-sm text-teal-900 underline") { "Refresh VAT codes" }
      if @check
        a(href: @check, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      p(role: "status", class: "mt-4 rounded-lg bg-amber-50 p-4") { "The VAT settings view is updating. Refresh before saving another change." } unless @data["status"] == "ready"
      if @draft && !@editable
        pre(class: "mt-4 whitespace-pre-wrap rounded-lg bg-amber-50 p-4 text-sm") { @draft[:attrs].to_json }
      end
      form_with(url: tenant_book_vat_rules_path(@tid, @bid), method: :get, class: "mt-5 flex flex-wrap items-end gap-3", data: { turbo: false }, id: "vat-settings-date") do |f|
        f.hidden_field(:vat_entry_id, value: @selected_entry) if @selected_entry
        div { f.label(:as_of, "Show settings valid on"); f.date_field(:as_of, value: @as_of.iso8601, required: true, class: FIELD) }
        f.submit("Show settings", class: BUTTON)
      end
      @data.fetch("vat_entries").each { |entry| code_card(entry) }
      orphans=@data.fetch("vat_rules").reject { |rule| @data.fetch("vat_entries").any? { |entry| entry["id"]==rule["vat_entry_id"] } }
      unless orphans.empty?
        details(class: "mt-5") { summary { "Settings for unavailable codes" }; orphans.each { |rule| settings_card(rule, "Unavailable code") } }
      end
      if @editable && (!@selected_entry || @data.fetch("vat_entries").any? { |entry| entry["id"]==@selected_entry && entry["active"] })
        entry=@data.fetch("vat_entries").find { |e| e["id"]==@selected_entry }
        h2(class: "mt-8 text-xl font-semibold") { entry ? "Configure #{entry['code']} · #{entry['name']}" : "Configure a VAT code" }
        p(class: "mt-2 text-sm text-stone-600") { "Choose a preset or enter custom settings. For a change, end the current settings the day before the new settings start; dates may not overlap." }
        presets
        rule_form(nil)
      end
    end
  end
  def code_card(entry)
    rules=@data.fetch("vat_rules").select { |rule| rule["vat_entry_id"]==entry["id"] }.sort_by { |rule| rule["valid_from"].to_s }
    date=@as_of.iso8601
    current=rules.select { |rule| rule["active"] && rule["valid_from"]<=date && (!rule["valid_until"] || rule["valid_until"]>=date) }
    upcoming=rules.select { |rule| rule["active"] && rule["valid_from"]>date }
    previous=rules-current-upcoming
    section(id: "vat-code-#{entry['id']}", class: "mt-6 rounded-xl border border-stone-200 bg-white p-5", data: { vat_code: entry["id"] }) do
      h2(class: "text-xl font-semibold") { "#{entry['code']} · #{entry['name']}" }
      p(class: "mt-1 text-sm text-stone-500") { entry["active"] ? "VAT code used on chart accounts" : "Inactive VAT code · retained for existing accounts and history" }
      p(role: "status", class: "mt-3 text-sm text-amber-900") { "Not configured for #{@as_of.iso8601}. This code cannot calculate VAT for that date until settings cover it." } if current.empty? && entry["active"]
      current.each { |rule| settings_card(rule, "Current settings") }
      upcoming.each { |rule| settings_card(rule, "Scheduled change") }
      if @editable && entry["active"]
        a(href: tenant_book_vat_rules_path(@tid, @bid, vat_entry_id: entry["id"], copy_from: current.first && current.first["id"], anchor: "vat_rule_create-new"), class: "mt-4 inline-block font-medium text-teal-900 underline") { current.empty? ? "Configure this VAT code" : "Schedule a change" }
        a(href: tenant_book_catalogues_path(@tid, @bid, anchor: "catalogue-#{entry['id']}"), class: "ml-4 text-sm text-teal-900 underline") { "Edit code/name" }
      end
      unless previous.empty?
        details(class: "mt-4 border-t pt-3") { summary(class: "cursor-pointer text-sm text-teal-900") { "Earlier or inactive settings (#{previous.length})" }; previous.reverse_each { |rule| settings_card(rule, "Earlier settings") } }
      end
    end
  end
  def settings_card(rule, label)
    section(id: "vat-rule-#{rule['id']}", class: "mt-4 rounded-lg bg-stone-50 p-4", data: { vat_settings: label }) do
      h3(class: "font-semibold") { "#{label} · #{rule['valid_from']} → #{rule['valid_until'] || 'Ongoing'}" }
      treatment={ "input"=>"Input VAT", "output"=>"Output VAT", "reverse_charge"=>"Reverse charge", "none"=>"No VAT" }[rule["direction"]] || rule["direction"]
      p(class: "mt-2 text-sm") { "#{treatment} · VAT #{percent(rule['rate_bps'])}% · Deductible #{percent(rule['deductible_bps'])}%#{rule['active'] ? '' : ' · Inactive settings'}" }
      preset_details(rule["preset"])
      posting_account_lines(rule["posting_accounts"])
      mapping_lines(rule.dig("mappings", "lines") || [])
      p(class: "mt-2 text-sm") { "VAT assessment comes from the import statement." } if rule["assessment_basis"]=="import_statement"
      if @editable
        if @draft && @draft.dig(:attrs, :rule_id)==rule["id"]
          rule_form(rule)
        else
          details(class: "mt-3") { summary(class: "cursor-pointer text-sm text-teal-900") { "Edit settings" }; rule_form(rule) }
        end
      end
      details(class: "mt-3 border-t pt-3") do
        summary(class: "cursor-pointer text-sm text-teal-900") { "Revision history (#{rule.fetch('history', []).length})" }
        rule.fetch("history", []).reverse_each do |h|
          p(class: "mt-3 text-sm") { "#{h['valid_from']} → #{h['valid_until'] || 'Ongoing'} · VAT #{percent(h['rate_bps'])}% · Deductible #{percent(h['deductible_bps'])}% · Revision #{h['version']}" }
          posting_account_lines(h["posting_accounts"])
          mapping_lines(h.dig("mappings", "lines") || [])
          p(class: "mt-1 text-xs text-stone-500") { "#{h['accepted_at']} · Actor #{h['actor_identity_id']} · Application #{h['application_id']}" }
        end
      end
    end
  end
  def presets
    items = Array(@data["presets"])
    return if items.empty?
    form_with(url: tenant_book_vat_rules_path(@tid, @bid), method: :get, class: "mt-6 flex flex-wrap items-end gap-3", data: { turbo: false }, id: "choose-vat-preset") do |f|
      div { f.hidden_field(:vat_entry_id, value: @selected_entry) if @selected_entry; f.label(:preset_id, "Danish preset"); f.select(:preset_id, items.map { |preset| [ "#{preset['id']} · #{preset['title']}", preset["id"] ] }, { include_blank: "Choose a Danish preset" }, class: FIELD, required: true) }
      f.submit("Use preset", class: BUTTON)
    end
    details(class: "mt-6 rounded-xl border border-stone-200 bg-white p-4", id: "danish-vat-presets") do
      summary(class: "cursor-pointer font-semibold text-teal-900") { "Danish VAT presets (#{items.length})" }
      p(class: "mt-3 text-sm text-stone-600") { "Templates for reviewed setup. The source-check date is not an effective start date. Deduction assumes eligible business use; adjust for mixed or private use. EU sales-list reporting is separate from VAT-return boxes." }
      items.each do |preset|
        section(class: "mt-4 rounded-lg border border-stone-200 p-4", id: "preset-#{preset['id']}") do
          h2(class: "font-semibold") { "#{preset['id']} · #{preset['title']}" }
          p(class: "mt-2 text-sm") { "#{preset['direction']} · VAT #{percent(preset['rate_bps'])}% · Deductible #{percent(preset['deductible_bps'])}%" }
          mapping_lines(preset.fetch("mappings"))
          preset_details(preset)
          a(href: tenant_book_vat_rules_path(@tid, @bid, preset_id: preset.fetch("id"), preset_version: preset.fetch("version"), vat_entry_id: @selected_entry, anchor: "vat_rule_create-new"), class: "mt-3 inline-block text-sm font-semibold text-teal-900 underline") { "Use #{preset['id']} preset" } if @editable
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
    lines.each { |m| p(class: "mt-2 text-xs text-stone-600") { "#{m['box']}: #{m['sign'] == -1 ? '−' : '+'} #{{ "net"=>"net amount (excluding VAT)", "vat"=>"VAT amount", "deductible_vat"=>"deductible VAT", "non_deductible_vat"=>"non-deductible VAT" }.fetch(m['component'], m['component'].to_s)}" } }
  end
  def posting_account_lines(mapping)
    p(class: "mt-2 text-sm") { "Non-deductible VAT follows the expense/asset account." } unless (mapping || {})["non_deductible"]
    (mapping || {}).each do |role, id|
      next unless id
      account = Array(@data["posting_accounts"]).find { |a| a["id"] == id }
      p(class: "mt-2 text-sm") { "#{role.tr('_', ' ').capitalize} posting: #{account ? account['number']+' · '+account['name'] : id}" }
    end
  end
  def rule_form(rule)
    action = rule ? "vat_rule_revise" : "vat_rule_create"
    draft = @draft && @draft[:action] == action && @draft.dig(:attrs, :rule_id) == (rule && rule["id"]) ? @draft[:attrs].deep_stringify_keys : nil
    values = draft || rule || {}
    mappings = draft ? (values["mappings"] || []) : values.dig("mappings", "lines") || []
    form_with(url: tenant_book_vat_rules_path(@tid, @bid), method: :patch, namespace: rule ? rule["id"] : "new-rule", id: "#{action}-#{rule && rule['id'] || 'new'}", class: "mt-4 rounded-lg border border-stone-200 bg-white p-4", data: { turbo: false }) do |f|
      p(class: "mb-3 font-medium text-amber-900") { values["preset_id"] ? "Preset draft — review the entry, dates, amounts and usage conditions before saving." : "Settings draft — existing settings above stay unchanged until you save" } if draft
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
          f.label(:vat_entry_id, "VAT code (same selection as chart accounts)")
          choices = @data.fetch("vat_entries").select { |e| e["active"] || e["id"] == values["vat_entry_id"] }.map { |e| [ "#{e['code']} · #{e['name']}", e["id"] ] }
          f.select(:vat_entry_id, choices, { selected: values["vat_entry_id"], include_blank: "Choose VAT code" }, class: FIELD, required: true, disabled: !!rule || (!@selected_entry.nil? && values["vat_entry_id"]==@selected_entry))
          f.hidden_field(:vat_entry_id, value: values["vat_entry_id"]) if rule || (!@selected_entry.nil? && values["vat_entry_id"]==@selected_entry)
        end
        %w[valid_from valid_until].each do |field|
          div { f.label(field, field == "valid_from" ? "Valid from" : "Valid until (optional)"); f.date_field(field, value: values[field], required: field == "valid_from", class: FIELD) }
        end
        div { f.label(:direction, "Treatment"); f.select(:direction, [ [ "Input VAT", "input" ], [ "Output VAT", "output" ], [ "Reverse charge", "reverse_charge" ], [ "No VAT", "none" ] ], { selected: values["direction"], include_blank: "Choose treatment" }, class: FIELD, required: true) }
        div { f.label(:assessment_basis, "VAT assessment"); f.select(:assessment_basis, [ [ "Calculate from net base", "net" ], [ "Import statement amount", "import_statement" ] ], { selected: values["assessment_basis"] || "net" }, class: FIELD) }
        div { f.label(:rate, "VAT rate (%)"); f.number_field(:rate, value: percent(values["rate_bps"]), step: "0.01", min: 0, max: 100, required: true, class: FIELD) }
        div { f.label(:deductible, "Deductible VAT share (%)"); f.number_field(:deductible, value: percent(values["deductible_bps"]), step: "0.01", min: 0, max: 100, required: true, class: FIELD) }
        div { f.label(:active, "Settings status"); f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: values["active"].to_s }, class: FIELD) } if rule
      end
      p(class: "mt-4 text-sm font-medium") { "VAT posting accounts" }
      p(class: "mt-1 text-sm text-stone-600") { "Map chart accounts for the saved posting preview. Missing mappings remain visible as preview issues; saving a rule does not post money." }
      div(class: "mt-3 grid gap-3 sm:grid-cols-2") do
        { "input"=>"Incoming VAT account", "output"=>"Outgoing VAT account" }.each do |role, title|
          div do
            label { title }
            select(name: "posting_accounts[#{role}]", aria_label: title, class: FIELD) do
              chosen=values.dig("posting_accounts", role)
              option(value: "", selected: chosen.blank?) { "Unmapped" }
              Array(@data["posting_accounts"]).each { |a| option(value: a["id"], selected: chosen==a["id"]) { "#{a['number']} · #{a['name']}#{a['active'] ? '' : ' · Inactive'}" } }
              option(value: chosen, selected: true) { "Unavailable account: #{chosen}" } if chosen.present? && !Array(@data["posting_accounts"]).any? { |a| a["id"]==chosen }
            end
          end
        end
      end
      p(class: "mt-3 text-sm text-stone-600") { values.dig("posting_accounts", "non_deductible").present? ? "Non-deductible VAT uses the separate account override shown under Advanced." : "Non-deductible VAT follows the expense/asset account automatically." }
      p(class: "mt-2 text-sm text-stone-600") { "VAT return reporting is filled by the selected Danish preset. Use Advanced only for custom reporting or a separate non-deductible account." }
      mapping_lines(mappings) unless mappings.empty?
      details(class: "mt-4 rounded border border-stone-200 p-3", data: { vat_advanced: true }, open: values.dig("posting_accounts", "non_deductible").present?) do
        summary(class: "cursor-pointer font-medium text-teal-900") { "Advanced" }
        p(class: "mt-3 text-sm text-stone-600") { "Reporting boxes are fields on the VAT return, not ledger accounts. Each row adds or subtracts the selected amount; unused rows stay blank." }
        label(class: "mt-4 block text-sm") { "Non-deductible VAT account override" }
        select(name: "posting_accounts[non_deductible]", aria_label: "Non-deductible VAT account override", class: FIELD) do
          chosen=values.dig("posting_accounts", "non_deductible")
          option(value: "", selected: chosen.blank?) { "Follow expense/asset account (default)" }
          Array(@data["posting_accounts"]).each { |a| option(value: a["id"], selected: chosen==a["id"]) { "#{a['number']} · #{a['name']}#{a['active'] ? '' : ' · Inactive'}" } }
          option(value: chosen, selected: true) { "Unavailable account: #{chosen}" } if chosen.present? && !Array(@data["posting_accounts"]).any? { |a| a["id"]==chosen }
        end
        p(class: "mt-4 text-sm font-medium") { "VAT return reporting" }
        4.times do |i|
          m = mappings[i] || {}
          div(class: "mt-3 grid gap-3 sm:grid-cols-3") do
            div { label { "VAT return box" }; input(name: "mappings[][box]", value: m["box"], maxlength: 60, aria_label: "Reporting box #{i+1}", class: FIELD) }
            div do
              label { "Amount to report" }
              select(name: "mappings[][component]", aria_label: "Amount component #{i+1}", class: FIELD) { option(value: "", selected: m["component"].blank?) { "Choose amount" }; [ [ "Net base", "net" ], [ "Assessed VAT", "vat" ], [ "Deductible VAT", "deductible_vat" ], [ "Non-deductible VAT", "non_deductible_vat" ] ].each { |label, value| option(value: value, selected: m["component"] == value) { label } } }
            end
            div { label { "Add or subtract" }; select(name: "mappings[][sign]", aria_label: "Sign #{i+1}", class: FIELD) { option(value: "1", selected: m["sign"] != -1) { "+ Add" }; option(value: "-1", selected: m["sign"] == -1) { "− Subtract" } } }
          end
        end
      end
      f.submit(draft && (@message || !values["preset_id"]) ? "Reapply settings draft" : rule ? "Save settings" : "Save dated settings", class: BUTTON)
    end
  end
end
