class Views::Journals::Show < Views::Base
  ERRORS = { "account_required"=>"Select a posting account.", "posting_account_required"=>"Headers and calculations cannot be journal accounts.", "account_inactive_or_retired"=>"The account is inactive or retired.", "choose_one_nonzero_side"=>"Enter a nonzero amount on exactly one side.", "inactive_vat_entry"=>"The selected VAT entry is inactive.", "vat_rule_missing"=>"No active VAT rule covers this date.", "invalid_amount"=>"Enter a signed whole-minor-unit VAT base; assessed overrides apply only to import statements.", "assessment_required"=>"Enter the signed VAT amount from the import statement.", "journal_unbalanced"=>"Debit and credit totals differ.", "two_nonzero_lines_required"=>"The journal needs at least two lines and a nonzero total.", "period_not_open"=>"The posting date is not in an open period.", "account_vat_not_selected"=>"This account has a VAT selection; confirm the explicit no-VAT choice or select a rule." }.freeze
  def initialize(data:, new_journal: false, requested_id: nil, requested_version: nil, work_token: nil, work_draft: nil, work_header: nil, decimal_separator: ".", review: nil, token: nil, editing: nil, extra_line: false, message: nil, check_url: nil, retry_url: nil, **options)
    super(**options, full_width: true)
    @requested_id, @requested_version = requested_id, requested_version
    @new_journal = new_journal
    @data, @review, @token, @editing, @extra, @message, @check, @retry = data, review, token, editing, extra_line, message, check_url, retry_url
    @work_token, @work_draft, @work_header, @decimal_separator = work_token, work_draft, work_header, decimal_separator
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data.dig("permissions", "prepare") && !check_url
  end
  def url(**query) = tenant_book_journals_path(@tid, @bid, **query)
  def view_template
    div(id: "vera-book-content", class: "min-w-0 break-words") do
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { "#{@data['book_name']} · #{@data['base_currency']}" }
      header(class: "mt-2 flex items-start justify-between gap-4") do
        h1(class: "min-w-0 text-3xl font-semibold") { @review ? "Review journal draft" : @new_journal ? "New journal" : @data["selected"] ? @data["selected"]["data"]["name"] : "Journal updating…" }
        journal_menu
      end
      p(class: "mt-4 text-sm text-stone-600", hidden: @data["work_rows_enabled"]) { "Prepare unposted journals with one posting date for all lines. Enter whole minor units (10000 means 100.00 in a two-decimal currency), debit or credit on each line, and optional references. Saving preserves a draft and its validation history." }
      p(class: "mt-3 text-sm text-stone-600", hidden: @data["work_rows_enabled"]) { "VAT quotes use an explicit signed net base and the effective rule for this date. They are separate from entered debit/credit amounts. No VAT counter-lines are generated. Draft checks do not grant posting authority; posting requires a later workflow." }
      p(role: "alert", class: "mt-4 rounded-lg bg-amber-50 p-4") { @message } if @message
      p(class: "mt-3 text-xs text-stone-500") { "Draft view #{@data['source_version']} · Latest accepted #{@data['latest_version']} · Book #{@data['book_status']} · #{@data['accounting_authority']} accounting" }
      p(role: "status", class: "mt-3 text-sm text-amber-900") { "A draft, setup or period view is updating. Refresh before preparing another review." } unless @data["status"] == "ready"
      if @check
        a(href: @check, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      if @data["work_rows_enabled"] && !@review && !@editing && !@data["historical"]
        render Components::JournalWork.new(data: @data, token: @work_token, separator: @decimal_separator, draft: @work_draft, header: @work_header)
      elsif @review
        reviewed
      elsif @editing
        if @data["selected"] && @message
          details(class: "mt-5", open: true) do
            summary(class: "cursor-pointer text-sm font-semibold text-teal-900") { "Current saved draft · Revision #{@data['selected']['version']}" }
            current = @data.fetch("selected")
            evidence(current["data"], current["validation"], current["contexts"])
          end
        end
        if @editable
          editor(@editing)
        else
          h2(class: "mt-6 text-xl font-semibold") { "Your unsaved draft" }
          p(class: "mt-2 text-sm text-stone-600") { "Your entries are shown below. Use Back to return to your form and review again after the views catch up." }
          p(class: "mt-3 text-sm") { "#{@editing['data']['name']} · #{@editing['data']['posting_date']} · #{@editing['data']['reference']}" }
          @editing["data"]["lines"].each_with_index do |line, index|
            a = @data.fetch("accounts").find { |row| row["id"] == line["account_id"] }
            p(class: "mt-2 text-sm") { "Line #{index + 1} · #{a ? account_label(a) : 'Unselected / unavailable account'} · Debit #{line['debit_minor']} · Credit #{line['credit_minor']} · #{line['reference']} · VAT base #{line['net_minor']} · Statement VAT #{line['assessed_vat_minor']}" }
          end
        end
      elsif @data["selected"]
        selected
      elsif @editable
        editor({ "data"=>{ "name"=>"", "posting_date"=>"", "reference"=>"", "lines"=>[] }, "expected_version"=>@data["latest_version"], "contexts"=>@data["contexts"] })
      end
    end
  end
  def journal_menu
    draft = @data["selected"]
    id = draft && draft["id"] || @requested_id
    refresh = @new_journal ? new_tenant_book_journals_path(@tid, @bid) : @review ? url(review_id: @review["review_id"]) : url(draft_id: id, version: @requested_version)
    render Components::ContextMenu.new(id: "journal-header-actions", label: "Journal actions") do
      a(href: url, role: "menuitem", class: "vera-menu-item") { "Back to journals" }
      if draft && @editable && !@data["historical"] && !@review
        a(href: details_dialog_tenant_book_journals_path(@tid, @bid, draft_id: id), role: "menuitem", data: { turbo_stream: true, journal_details_link: true }, class: "vera-menu-item") { "Edit journal details" }
      else
        button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Edit journal details" }
      end
      if draft && @editable && !@data["historical"] && !@review
        a(href: delete_dialog_tenant_book_journals_path(@tid, @bid, draft_id: id), role: "menuitem", data: { turbo_stream: true }, class: "vera-menu-item text-red-800") { "Delete journal" }
      else
        button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Delete journal" }
      end
      if draft
        a(href: history_tenant_book_journals_path(@tid, @bid, draft_id: id), role: "menuitem", data: { turbo_stream: true }, class: "vera-menu-item") { "Show history" }
      else
        button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Show history" }
      end
      if draft || @review
        a(href: posting_preview_tenant_book_journals_path(@tid, @bid, draft_id: @review ? nil : id, review_id: @review && @review["review_id"], version: @requested_version), role: "menuitem", data: { turbo_stream: true }, class: "vera-menu-item") { "Saved posting preview · Unposted" }
      else
        button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Saved posting preview · Unposted" }
      end
      a(href: refresh, role: "menuitem", class: "vera-menu-item") { "Refresh journal" }
    end
  end
  def evidence(data, validation, contexts)
    h2(class: "mt-6 text-xl font-semibold") { "#{data['name']} · #{data['posting_date']}" }
    p(class: "mt-2 text-sm") { "Reference: #{data['reference']}" }
    p(class: "mt-2 text-sm font-semibold") { validation["status"] == "prepared" ? "Unposted draft · Checks passed at review" : "Unposted draft · Needs attention" }
    p(class: "mt-2 text-sm") { "Debit #{validation['debit_minor']} · Credit #{validation['credit_minor']} · Difference #{validation['difference_minor']} minor units" }
    p(class: "mt-2 text-xs text-stone-500") { "Setup revision #{contexts['setup_version']} · Period revision #{contexts['period_version']} · Book revision #{contexts['book_version']}" }
    period = validation["period"]
    p(class: "mt-2 text-sm") { period ? "Period: #{period['name']} · #{period['status']} · Revision #{period['version']}" : "No period covers this date." }
    validation.fetch("errors").each { |error| p(role: "status", class: "mt-2 text-sm text-amber-900") { ERRORS.fetch(error, error) } }
    data.fetch("lines").each_with_index do |line, index|
      v = validation.fetch("lines").find { |r| r["id"] == line["id"] }
      section(class: "mt-4 rounded-lg border border-stone-200 bg-white p-4", data: { journal_line: index + 1 }) do
        h3(class: "font-semibold") { "Line #{index + 1} · #{v['account'] ? account_label(v['account']) : 'No account'}" }
        p(class: "mt-2 text-sm") { "Debit #{line['debit_minor']} · Credit #{line['credit_minor']} · #{line['reference']}" }
        (v.fetch("errors") + v.fetch("warnings")).each { |error| p(role: "status", class: "mt-2 text-sm text-amber-900") { ERRORS.fetch(error, error) } }
        q = v["vat"]
        if q && !q["error"]
          p(class: "mt-2 text-sm") { "VAT #{q['code']} · #{q['direction']} · Net base #{line['net_minor']} · Assessed VAT #{q['amounts']['vat']} · Deductible #{q['amounts']['deductible_vat']} · Non-deductible #{q['amounts']['non_deductible_vat']}" }
          p(class: "mt-1 text-xs text-stone-500") { "VAT rule #{q['rule_id']} · Revision #{q['rule_version']} · Assessment #{q['assessment_basis']} · Invoice preview #{q['invoice_total_minor']}" }
        elsif !q
          p(class: "mt-2 text-sm text-stone-500") { "No VAT calculation selected." }
        end
      end
    end
    if validation["reporting"].any?
      h3(class: "mt-4 font-semibold") { validation["vat_complete"] ? "VAT reporting preview" : "Partial VAT reporting preview — resolve VAT errors" }
      validation["reporting"].each { |box, value| p(class: "mt-2 text-sm") { "#{box}: #{value} minor units" } }
    end
  end
  def reviewed
    plan = @review.fetch("plan")
    p(class: "mt-4 text-sm") { "Private review expires #{@review['expires_at']}. This saves an unposted draft, including any listed issues." }
    if plan["before"]
      details(class: "mt-4") do
        summary(class: "cursor-pointer text-sm text-teal-900") { "Previously saved draft" }
        evidence(plan["before"]["data"], plan["before"]["validation"], plan["before"]["contexts"])
      end
    end
    evidence(plan["data"], plan["validation"], plan["contexts"])
    if @token
      form_with(url: url, method: :patch, id: "accept-journal", data: { turbo: false }) do |f|
        f.hidden_field(:form_token, value: @token)
        f.submit(plan["validation"]["status"] == "prepared" ? "Save reviewed draft" : "Save draft with issues", class: BUTTON)
      end
    end
    a(href: url(review_id: @review["review_id"], edit: "1"), class: "mt-4 block text-sm text-teal-900 underline") { "Continue editing this draft" } if @editable && !@review["accepted_command_id"]
  end
  def selected
    draft = @data.fetch("selected")
    p(role: "status", class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm") { "The book, chart, VAT rules or periods changed since this validation. Review again before relying on the checks." } if @data["validation_stale"]
    p(class: "mt-4 text-sm text-stone-500") { "Saved draft revision #{draft['version']}" }
    Array(draft["data"]["rows"]).each do |row|
      p(class: "mt-2 text-sm") { "Posting #{row['posting_id']} · #{row['reference']}#{row['void'] ? ' · Voided — number retained' : ''}" }
    end
    evidence(draft["data"], draft["validation"], draft["contexts"])
    if @editable
      a(href: @data["work_rows_enabled"] ? url(draft_id: draft["id"]) : url(draft_id: draft["id"], edit: "1"), class: "mt-4 block text-sm text-teal-900 underline") { @data["work_rows_enabled"] ? "Open current work journal" : "Edit / review current draft" }
    end
  end
  def editor(values)
    data = values.fetch("data")
    lines = data.fetch("lines").dup
    lines << {} if @extra || lines.empty?
    lines << {} if lines.length == 1 && data["lines"].empty?
    lines = lines.first(100)
    h2(class: "mt-8 text-xl font-semibold") { values["draft_id"] ? "Edit unposted draft" : "New unposted draft" }
    form_with(url: review_tenant_book_journals_path(@tid, @bid), method: :post, id: "journal-editor", data: { turbo: false }) do |f|
      f.hidden_field(:draft_id, value: values["draft_id"])
      f.hidden_field(:expected_draft_version, value: values["expected_draft_version"])
      f.hidden_field(:expected_version, value: values["expected_version"])
      values.fetch("contexts").each { |key, value| input(type: "hidden", name: "contexts[#{key}]", value: value) }
      div(class: "mt-4 grid gap-3 sm:grid-cols-3") do
        div { f.label(:name, "Draft name"); f.text_field(:name, value: data["name"], maxlength: 120, required: true, class: FIELD) }
        div { f.label(:posting_date, "Posting date (all lines)"); f.date_field(:posting_date, value: data["posting_date"], required: true, class: FIELD) }
        div { f.label(:reference, "Reference (optional)"); f.text_field(:reference, value: data["reference"], maxlength: 120, class: FIELD) }
      end
      lines.each_with_index do |line, index|
        saved = Array(values.dig("saved_validation", "lines")).find { |l| l["id"] == line["id"] }
        fieldset(class: "mt-5 rounded-xl border border-stone-200 bg-white p-4") do
          legend(class: "px-2 text-sm font-semibold") { "Journal line #{index + 1}" }
          input(type: "hidden", name: "lines[#{index}][id]", value: line["id"])
          div(class: "grid gap-3 sm:grid-cols-2") do
            div do
              label(for: "journal-line-#{index}-account", class: "text-sm") { "Posting account" }
              select(id: "journal-line-#{index}-account", name: "lines[#{index}][account_id]", class: FIELD) do
                option(value: "", selected: line["account_id"].blank?) { "Choose account" }
                @data.fetch("accounts").each { |a| option(value: a["id"], selected: a["id"] == line["account_id"]) { account_label(a) } }
                if line["account_id"].present? && @data.fetch("accounts").none? { |a| a["id"] == line["account_id"] }
                  option(value: line["account_id"], selected: true) { "Unavailable: #{saved && saved['account'] ? account_label(saved['account']) : line['account_id']}" }
                end
              end
            end
            %w[debit_minor credit_minor reference net_minor assessed_vat_minor].each do |key|
              div do
                label(for: "journal-line-#{index}-#{key}", class: "text-sm") { { "debit_minor"=>"Debit (minor units)", "credit_minor"=>"Credit (minor units)", "reference"=>"Line reference", "net_minor"=>"Signed VAT net base (optional)", "assessed_vat_minor"=>"Import-statement VAT (optional)" }.fetch(key) }
                input(id: "journal-line-#{index}-#{key}", name: "lines[#{index}][#{key}]", type: key == "reference" ? "text" : "number", step: key == "reference" ? nil : "1", value: line[key], class: FIELD, maxlength: key == "reference" ? 120 : nil)
              end
            end
            div do
              label(for: "journal-line-#{index}-vat", class: "text-sm") { "VAT calculation" }
              select(id: "journal-line-#{index}-vat", name: "lines[#{index}][vat_entry_id]", class: FIELD) do
                option(value: "", selected: line["vat_entry_id"].blank?) { "No VAT calculation" }
                @data.fetch("vat_entries").each { |v| option(value: v["id"], selected: line["vat_entry_id"] == v["id"]) { "#{v['code']} · #{v['name']}" } }
                option(value: line["vat_entry_id"], selected: true) { "Unavailable VAT entry: #{line['vat_entry_id']}" } if line["vat_entry_id"].present? && @data.fetch("vat_entries").none? { |v| v["id"] == line["vat_entry_id"] }
              end
            end
          end
          label(class: "mt-3 flex items-center gap-2 text-sm") { input(type: "checkbox", name: "lines[#{index}][remove]", value: "1"); plain "Remove this line from the draft" }
        end
      end
      f.submit("Review journal draft", class: BUTTON)
      button(type: "submit", name: "intent", value: "add_line", class: "ml-4 text-sm text-teal-900 underline", formnovalidate: true) { "Add journal line" } if lines.length < 100
    end
  end
  def account_label(a) = "#{a['number']} · #{a['name']}#{a['active'] && !a['retired'] ? '' : ' · Inactive / retired'}"
end
