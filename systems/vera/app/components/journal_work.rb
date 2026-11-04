class Components::JournalWork < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :journal_work_editor
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(data:, token:, separator:, draft: nil, header: nil)
    @data, @token, @separator, @draft, @header = data, token, separator, draft, header
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data.dig("permissions", "prepare")
  end
  def view_template
    selected = @data["selected"]
    unless selected
      unless @editable
        journal_work_editor(data: { pending: "true" }) { p(role: "status", class: "mt-4 text-sm text-stone-600") { "The saved journal is updating…" } } if @data["status"] == "pending"
        return
      end
      h2(class: "mt-6 text-xl font-semibold") { "Create draft journal" }
      form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, id: "journal-create", data: { turbo: false }) do |f|
        f.hidden_field(:form_token, value: @token.call("journal_create"))
        fences(f)
        div(class: "mt-4 grid gap-4 sm:grid-cols-3") do
          div { f.label(:name, "Draft name"); f.text_field(:name, value: @header && @header["name"], required: true, maxlength: 120, class: FIELD) }
          div { f.label(:posting_date, "Posting date"); f.date_field(:posting_date, value: @header && @header["posting_date"], required: true, class: FIELD) }
          div { f.label(:reference, "Reference"); f.text_field(:reference, value: @header && @header["reference"], maxlength: 120, class: FIELD) }
        end
        f.submit("Create draft journal", class: BUTTON)
      end
      return
    end
    header = selected.fetch("data")
    h2(class: "mt-6 text-xl font-semibold") { "Journal lines" }
    p(class: "mt-2 text-sm text-stone-600") { [ header["posting_date"], header["reference"].presence, "Work in progress" ].compact.join(" · ") }
    p(class: "mt-2 text-sm text-stone-600") { "Type / followed by an account number or name; use ↑/↓ and Enter to choose. Enter saves the current row; Escape cancels edits. Amounts use #{@separator} as the decimal point, without thousands separators." }
    p(class: "mt-2 text-sm text-stone-600") { "Posting IDs are assigned on save from one book sequence and remain on voided rows. Authorization, verification and final posting follow in a later workflow." }
    if @data["validation_stale"]
      p(role: "status", class: "mt-3 rounded-lg bg-amber-50 p-3 text-sm") { "Account, VAT or period configuration changed. Save uses a fresh validation; previous evidence stays in History." }
    end
    if @draft && !@editable
      p(role: "status", class: "mt-3 rounded bg-amber-50 p-3 text-sm") { "Your unsaved row: #{@draft['reference']} · #{@draft['debit_label']} · #{@draft['amount']} · #{@draft['credit_label']}. Use Back to return to the form after the view catches up." }
    end
    if @editable
      details(class: "mt-4") do
        summary(class: "cursor-pointer text-sm text-teal-900") { "Edit journal details" }
        form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, data: { turbo: false, journal_details: true }) do |f|
          f.hidden_field(:form_token, value: @token.call("journal_details", selected["id"]))
          f.hidden_field(:draft_id, value: selected["id"])
          f.hidden_field(:expected_draft_version, value: selected["version"])
          fences(f)
          values = @header || header
          div(class: "mt-3 grid gap-3 sm:grid-cols-3") do
            div { f.label(:name, "Draft name"); f.text_field(:name, value: values["name"], required: true, maxlength: 120, class: FIELD) }
            div { f.label(:posting_date, "Posting date"); f.date_field(:posting_date, value: values["posting_date"], required: true, class: FIELD) }
            div { f.label(:reference, "Reference"); f.text_field(:reference, value: values["reference"], maxlength: 120, class: FIELD) }
          end
          f.submit("Save journal details", class: BUTTON)
        end
      end
    end
    rows = header["rows"] || legacy_rows(header)
    journal_work_editor(class: "mt-5 block min-w-0", data: { lookup_url: accounts_tenant_book_journals_path(@tid, @bid), preview_url: row_preview_tenant_book_journals_path(@tid, @bid), setup_version: @data.dig("contexts", "setup_version"), decimal_separator: @separator, pending: (@data["status"] == "pending").to_s }) do
      p(role: "status", aria_live: "polite", data: { work_status: true }, class: "mb-3 text-sm text-amber-900")
      div(class: "max-w-full overflow-x-auto rounded-lg border border-stone-200 bg-white") do
        div(class: "min-w-[1350px]") do
          div(class: "grid grid-cols-[80px_130px_40px_190px_120px_130px_190px_120px_160px_80px] gap-2 border-b border-stone-200 bg-stone-100 p-3 text-xs font-semibold uppercase text-stone-600") do
            [ "Posting ID", "Line reference", "Files", "Debit account", "Debit amount", "VAT included", "Credit account", "Credit amount", "VAT", "" ].each { |label| div { label } }
          end
          row_form(selected, { "id"=>nil, "reference"=>"", "amount_minor"=>0, "amount_basis"=>nil, "basis_override"=>false, "void"=>false }) if @editable && rows.length < 100
          rows.sort_by { |row| -(row["posting_id"] || 0) }.each { |row| row_form(selected, row) }
          p(class: "p-3 text-sm text-stone-600") { "This journal has 100 rows. Create another journal to continue; posting IDs continue in the same book sequence." } if @editable && rows.length >= 100
        end
      end
    end
  end
  def row_form(selected, row)
    is_draft = @draft && @draft["id"] == row["id"]
    values = is_draft ? row.merge(@draft) : row
    editing = is_draft || row["id"].nil?
    label = row["posting_id"] ? row["posting_id"].to_s : row["id"] ? "On next save" : "On save"
    form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, id: "work-row-#{row['id'] || 'new'}", class: "grid grid-cols-[80px_130px_40px_190px_120px_130px_190px_120px_160px_80px] items-start gap-2 border-b border-stone-200 p-3 #{row['void'] ? 'bg-stone-100' : ''}", data: { turbo: false, work_row: true, draft: is_draft.to_s, editing: editing.to_s }) do |f|
      f.hidden_field(:form_token, value: @token.call("journal_row", selected["id"], row["id"]))
      f.hidden_field(:draft_id, value: selected["id"])
      f.hidden_field(:row_id, value: row["id"])
      f.hidden_field(:expected_draft_version, value: selected["version"])
      f.hidden_field(:void, value: row["void"].to_s)
      fences(f)
      output(class: "py-2 text-sm font-semibold tabular-nums", data: { posting_id: row["posting_id"] }) { label }
      div do
        f.text_field(:reference, value: values["reference"], maxlength: 120, aria_label: "Line reference #{label}", class: "w-full rounded border border-stone-300 px-2 py-2 text-sm", readonly: !editing)
        span(class: "mt-1 block text-xs text-stone-500") { "Voided — number retained" } if row["void"]
      end
      div do
        if row["posting_id"]
          a(href: attachments_tenant_book_journals_path(@tid, @bid, row_id: row["id"]), aria_label: "Attachments for posting #{label}", class: "inline-flex whitespace-nowrap rounded px-1 py-2 text-sm text-teal-900", data: { work_attachment: true }) { "📎 #{Array(row['attachments']).length}" }
        else
          span(title: "Save the row to attach enclosures", aria_label: "Save row before adding attachments", class: "block px-2 py-2 text-stone-400") { "📎" }
        end
      end
      lookup(f, values, "debit", editing)
      div do
        input(name: "amount", value: is_draft ? @draft["amount"] : row["id"] ? money(row["amount_minor"]) : "", type: "text", inputmode: "decimal", autocomplete: "off", aria_label: "Debit amount #{label}", readonly: !editing, class: "w-full rounded border border-stone-300 px-2 py-2 text-sm", data: { work_amount: true })
      end
      div do
        input(type: "hidden", name: "amount_basis", value: values["amount_basis"], data: { work_basis: true })
        override = values.key?("basis_override") ? [ true, "true" ].include?(values["basis_override"]) : !values["amount_basis"].nil?
        input(type: "hidden", name: "basis_override", value: override.to_s, data: { basis_override: true })
        label(class: "mt-1 flex items-center gap-1 text-xs") do
          input(type: "checkbox", checked: values["amount_basis"] == "gross", disabled: !editing, aria_label: "VAT included #{label}", data: { work_included: true })
          plain "VAT included"
        end
        span(class: "block text-xs text-stone-500", data: { basis_label: true }) { override ? "Posting override" : "Account default" }
        button(type: "button", hidden: !editing || !override, data: { basis_default: true }, class: "text-xs text-teal-900 underline") { "Use account default" }
      end
      lookup(f, values, "credit", editing)
      div do
        credit_override = is_draft ? @draft["credit_override"] == "true" : (!row["credit_amount_minor"].nil? || (row["id"].present? && !row.key?("credit_total_minor")))
        input(type: "hidden", name: "credit_override", value: credit_override.to_s, data: { credit_override: true })
        input(type: "text", name: "credit_amount", value: is_draft ? @draft["credit_amount"] : row["id"] ? credit_value(row) : "", inputmode: "decimal", autocomplete: "off", aria_label: "Credit amount #{label}", readonly: !editing, class: "w-full rounded border border-stone-300 px-2 py-2 text-sm", data: { work_credit: true })
        button(type: "button", hidden: !editing || !credit_override, data: { credit_default: true }, class: "text-xs text-teal-900 underline") { "Use calculated amount" }
      end
      output(class: "break-words py-2 text-xs text-stone-600", data: { work_vat: true }) { vat_text(selected, row) }
      div(class: "flex flex-wrap gap-2") do
        button(type: "button", hidden: editing, data: { work_edit: true }, class: "text-sm text-teal-900 underline") { "Edit" } if @editable && !row["void"]
        f.submit("Save", class: "rounded bg-teal-950 px-3 py-2 text-sm text-white", hidden: !editing, data: { work_save: true }) if @editable
        button(type: "button", hidden: !editing, data: { work_cancel: true }, class: "text-xs text-teal-900 underline") { "Cancel" } if @editable
        button(type: "submit", name: "void", value: (!row["void"]).to_s, formnovalidate: true, class: "text-xs text-stone-600 underline") { row["void"] ? "Restore" : "Void" } if @editable && row["posting_id"]
      end
    end
  end
  def lookup(f, row, side, editing)
    a = @data["accounts"].find { |a| a["id"] == row[side+"_account_id"] }
    unavailable = a.nil? && row[side+"_account_id"].present?
    if unavailable
      saved = Array(@data.dig("selected", "validation", "lines")).find { |l| [ row[side+"_line_id"], row["id"] ].compact.include?(l["id"]) && l.dig("account", "id") == row[side+"_account_id"] }
      a = saved && saved["account"]
    end
    label = @draft && @draft["id"] == row["id"] ? @draft[side+"_label"] : a ? "#{a['number']} · #{a['name']}#{unavailable ? ' · Unavailable' : a['active'] ? '' : ' · Inactive'}" : row[side+"_account_id"] ? "Unavailable account" : ""
    div(class: "relative", data: { account_lookup: side }) do
      input(type: "hidden", name: side+"_account_id", value: row[side+"_account_id"], data: { account_id: true })
      input(type: "text", name: side+"_label", value: label, readonly: !editing, autocomplete: "off", placeholder: "/ account number or name", role: "combobox", aria: { label: "#{side.capitalize} posting account", autocomplete: "list", expanded: "false" }, class: "w-full rounded border border-stone-300 px-2 py-2 text-sm", data: { account_search: true, account_basis: a && a["vat_basis"], account_vat: a && a["vat_entry_id"] })
      div(hidden: true, role: "listbox", popover: "manual", class: "absolute z-20 mt-1 max-h-60 w-72 overflow-y-auto rounded border border-stone-300 bg-white shadow-lg", data: { account_results: true })
    end
  end
  def fences(f)
    f.hidden_field(:expected_version, value: @data["latest_version"])
    @data.fetch("contexts").each { |k, v| input(type: "hidden", name: "contexts[#{k}]", value: v) }
  end
  def legacy_rows(data)
    data["lines"].map { |l| { "id"=>l["id"], "reference"=>l["reference"], "debit_account_id"=>l["debit_minor"]>0 ? l["account_id"] : nil, "credit_account_id"=>l["credit_minor"]>0 ? l["account_id"] : nil, "amount_minor"=>l["debit_minor"]+l["credit_minor"], "amount_basis"=>"net", "basis_override"=>true, "void"=>false } }
  end
  def vat_text(selected, row)
    entries = selected.dig("validation", "lines") || []
    entries = entries.select { |l| [ row["debit_line_id"], row["credit_line_id"], row["id"] ].compact.include?(l["id"]) }
    values = entries.filter_map { |l| l["vat"] && (l["vat"]["error"] ? l["vat"]["error"].tr("_", " ") : "#{l['vat']['code']}: #{money(l['vat']['amounts']['vat'])}") }
    values = values.each_with_index.map { |value, i| "#{i.zero? ? 'Debit' : 'Credit'} #{value}" } if values.length > 1
    values.empty? ? "No VAT configured" : values.join(" · ")
  end
  def credit_value(row)
    value = row.key?("credit_total_minor") ? row["credit_total_minor"] : row["credit_amount_minor"] || row["amount_minor"]
    value.nil? ? "" : money(value)
  end
  def money(value) = JournalMoney.format(value, separator: @separator)
end
