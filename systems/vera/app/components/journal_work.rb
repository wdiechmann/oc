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
    p(class: "mt-2 text-sm text-stone-600") { "Type two or more characters to search anywhere in account numbers, names, VAT or categories; use ↑/↓ and Enter or click a result to choose. Home/End go to the first/last row; Page Up/Down go to the previous/next row. Arrow keys navigate account results while searching and keep normal behavior in other inputs. Enter saves the current row and creates the next numbered line; Escape cancels edits. Amounts use #{@separator} as the decimal point, without thousands separators." }
    p(class: "mt-2 text-sm text-stone-600") { "New lines are created immediately with an ID from the book sequence and can receive attachments before accounts or amounts are entered. IDs remain on voided rows. Authorization, verification and final posting follow in a later workflow." }
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
    @entry_row_id = rows.select { |row| blank_row?(row) }.max_by { |row| row["posting_id"] || 0 }&.fetch("id")
    journal_work_editor(class: "mt-5 block min-w-0", data: { lookup_url: accounts_tenant_book_journals_path(@tid, @bid), preview_url: row_preview_tenant_book_journals_path(@tid, @bid), setup_version: @data.dig("contexts", "setup_version"), decimal_separator: @separator, pending: (@data["status"] == "pending").to_s }) do
      p(role: "status", aria_live: "polite", data: { work_status: true }, class: "mb-3 text-sm text-amber-900")
      div(class: "journal-grid-container max-w-full overflow-x-auto rounded-lg border border-stone-200 bg-white") do
        div(class: "journal-grid") do
          div(class: "journal-columns grid gap-2 border-b border-stone-200 bg-stone-100 p-3 text-xs font-semibold uppercase text-stone-600") do
            [ "ID", "Line reference", "Files", "Debit account", "Debit amount", "VAT", "Credit account", "Credit amount", "VAT", "" ].each_with_index { |label, index| div(class: [ 4, 5, 7, 8 ].include?(index) ? "text-right" : nil, title: index == 5 ? "Checked: debit amount includes VAT. Unchecked: VAT is added. Defaults to the selected account; each posting can override it." : index == 8 ? "Calculated VAT amount; hover over a row amount for its account and rule details." : nil) { label } }
          end
          new_line_form(selected) if @editable && rows.length < 100
          rows.sort_by { |row| -(row["posting_id"] || 0) }.each { |row| row_form(selected, row) }
          p(class: "p-3 text-sm text-stone-600") { "This journal has 100 rows. Create another journal to continue; posting IDs continue in the same book sequence." } if @editable && rows.length >= 100
        end
      end
    end
  end
  def new_line_form(selected)
    form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, id: "work-row-new", data: { turbo: false }) do |f|
      f.hidden_field(:form_token, value: @token.call("journal_row", selected["id"]))
      f.hidden_field(:draft_id, value: selected["id"])
      f.hidden_field(:expected_draft_version, value: selected["version"])
      fences(f)
      { reference: "", amount: "0", basis_override: "false", void: "false" }.each { |key, value| f.hidden_field(key, value: value) }
      f.submit("New line", class: "m-3 rounded border border-teal-800 px-3 py-2 text-sm text-teal-900")
    end
  end
  def blank_row?(row)
    !row["void"] && row["reference"].blank? && row["debit_account_id"].blank? && row["credit_account_id"].blank? && row["amount_minor"].to_i.zero?
  end
  def row_form(selected, row)
    is_draft = @draft && @draft["id"] == row["id"]
    values = is_draft ? row.merge(@draft) : row
    editing = is_draft || (@editable && !@draft && row["id"] == @entry_row_id)
    credit_override = is_draft ? @draft["credit_override"] == "true" : (!row["credit_amount_minor"].nil? || (row["id"].present? && !row.key?("credit_total_minor")))
    override = values.key?("basis_override") ? [ true, "true" ].include?(values["basis_override"]) : !values["amount_basis"].nil?
    label = row["posting_id"] ? row["posting_id"].to_s : row["id"] ? "On next save" : "On save"
    form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, id: "work-row-#{row['id'] || 'new'}", class: "journal-columns grid items-start gap-2 border-b border-stone-200 p-3 #{row['void'] ? 'bg-stone-100' : ''}", data: { turbo: false, work_row: true, draft: is_draft.to_s, editing: editing.to_s }) do |f|
      f.hidden_field(:form_token, value: @token.call("journal_row", selected["id"], row["id"]))
      f.hidden_field(:draft_id, value: selected["id"])
      f.hidden_field(:row_id, value: row["id"])
      f.hidden_field(:expected_draft_version, value: selected["version"])
      f.hidden_field(:intent, value: "", data: { row_intent: true })
      f.hidden_field(:void, value: row["void"].to_s)
      fences(f)
      output(class: "py-2 text-sm font-semibold tabular-nums", data: { posting_id: row["posting_id"] }) { label }
      div do
        f.text_field(:reference, value: values["reference"], maxlength: 120, aria_label: "Line reference #{label}", class: "min-w-0 w-full rounded border border-stone-300 px-2 py-2 text-sm", readonly: !editing)
        span(class: "mt-1 block text-xs text-stone-500") { "Voided — number retained" } if row["void"]
      end
      div do
        if row["posting_id"]
          a(href: attachments_tenant_book_journals_path(@tid, @bid, row_id: row["id"]), aria_label: "Attachments for posting #{label}", class: "inline-flex whitespace-nowrap rounded px-1 py-2 text-sm text-teal-900", id: "attachments-#{row['id']}", data: { work_attachment: true, turbo: true, turbo_stream: true }) { "📎 #{Array(row['attachments']).length}" }
        else
          span(title: "Save the row to attach enclosures", aria_label: "Save row before adding attachments", class: "block px-2 py-2 text-stone-400") { "📎" }
        end
      end
      lookup(f, values, "debit", editing)
      div do
        input(name: "amount", value: is_draft ? @draft["amount"] : row["id"] ? money(row["amount_minor"]) : "", type: "text", inputmode: "decimal", autocomplete: "off", aria_label: "Debit amount #{label}", readonly: !editing, class: "min-w-0 w-full rounded border border-stone-300 px-2 py-2 text-right text-sm", data: { work_amount: true })
      end
      div do
        input(type: "hidden", name: "amount_basis", value: values["amount_basis"], data: { work_basis: true })
        input(type: "hidden", name: "basis_override", value: override.to_s, data: { basis_override: true })
        input(type: "checkbox", checked: values["amount_basis"] == "gross", disabled: !editing, aria_label: "VAT included #{label}", title: basis_title(values), class: "mt-3 ml-auto block", data: { work_included: true })
      end
      lookup(f, values, "credit", editing)
      div do
        input(type: "hidden", name: "credit_override", value: credit_override.to_s, data: { credit_override: true })
        input(type: "text", name: "credit_amount", value: is_draft ? @draft["credit_amount"] : row["id"] ? credit_value(row) : "", inputmode: "decimal", autocomplete: "off", aria_label: "Credit amount #{label}", readonly: !editing, class: "min-w-0 w-full rounded border border-stone-300 px-2 py-2 text-right text-sm", data: { work_credit: true })
      end
      vat = vat_display(selected, row)
      output(class: "py-2 text-right text-sm tabular-nums text-stone-600", title: vat[:explanation], aria_label: vat[:explanation], data: { work_vat: true }) { vat[:amount] }
      render Components::ContextMenu.new(id: "work-actions-#{row['id'] || 'new'}", label: "More actions for posting #{label}", hidden: !@editable) do
        button(type: "button", hidden: !editing || !credit_override, data: { credit_default: true }, role: "menuitem", class: "vera-menu-item") { "Use calculated amount" }

        button(type: "button", hidden: !editing || !override, data: { basis_default: true }, role: "menuitem", class: "vera-menu-item") { "Use account default" }
        button(type: "button", hidden: editing, data: { work_edit: true }, role: "menuitem", class: "vera-menu-item") { "Edit" } if @editable && !row["void"]
        button(type: "submit", role: "menuitem", class: "vera-menu-item", hidden: !editing, data: { work_save: true }) { "Save" } if @editable
        button(type: "button", hidden: !editing, data: { work_cancel: true }, role: "menuitem", class: "vera-menu-item") { "Cancel" } if @editable
        button(type: "submit", name: "void", value: (!row["void"]).to_s, formnovalidate: true, role: "menuitem", class: "vera-menu-item") { row["void"] ? "Restore" : "Void" } if @editable && row["posting_id"]
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
    div(class: "relative min-w-0", data: { account_lookup: side }) do
      input(type: "hidden", name: side+"_account_id", value: row[side+"_account_id"], data: { account_id: true })
      input(type: "text", name: side+"_label", value: label, readonly: !editing, autocomplete: "off", placeholder: "Account number or name (2+ chars)", role: "combobox", aria: { label: "#{side.capitalize} posting account", autocomplete: "list", expanded: "false" }, class: "min-w-0 w-full rounded border border-stone-300 px-2 py-2 text-sm", data: { account_search: true, account_basis: a && a["vat_basis"], account_vat: a && a["vat_entry_id"] })
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
  def basis_title(row)
    override = [ true, "true" ].include?(row["basis_override"])
    source = override ? "Posting override" : "Account default"
    basis = { "gross"=>"VAT included in debit amount", "net"=>"VAT added to debit amount" }[row["amount_basis"]] || "VAT inclusion unspecified; select an account default or toggle this posting"
    "#{source}: #{basis}. Toggle to override this posting; Use account default restores the account setting."
  end
  def vat_display(selected, row)
    entries = Array(selected.dig("validation", "lines")).select { |l| [ row["debit_line_id"], row["credit_line_id"], row["id"] ].compact.include?(l["id"]) }
    quotes = entries.filter_map { |l| l["vat"] }
    errors = quotes.filter_map { |q| q["error"]&.tr("_", " ") }
    explanation = quotes.map { |q| q["error"] ? q["error"].tr("_", " ") : "#{q['code']}: #{money(q['amounts']['vat'])}" }.join(" · ")
    { amount: errors.any? ? "—" : money(quotes.sum { |q| q.dig("amounts", "vat") || 0 }), explanation: explanation.presence || "No VAT configured" }
  end
  def credit_value(row)
    value = row.key?("credit_total_minor") ? row["credit_total_minor"] : row["credit_amount_minor"] || row["amount_minor"]
    value.nil? ? "" : money(value)
  end
  def money(value) = JournalMoney.format(value, separator: @separator)
end
