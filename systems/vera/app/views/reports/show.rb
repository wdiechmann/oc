class Views::Reports::Show < Views::Base
  include Phlex::Rails::Helpers::NumberWithPrecision
  def initialize(data:, review: nil, token: nil, editing: nil, balances: nil, extra_line: false, message: nil, check_url: nil, retry_url: nil, **options)
    super(**options)
    @data, @review, @token, @editing, @balances, @extra_line, @message, @check, @retry = data, review, token, editing, balances || data["balances"] || {}, extra_line, message, check_url, retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data.dig("permissions", "configure") && !check_url
  end
  def url(**query) = tenant_book_reports_path(@tid, @bid, **query)
  def view_template
    div(id: "vera-book-content", class: "min-w-0 break-words") do
      a(href: tenant_book_chart_path(@tid, @bid), class: "text-teal-900 underline") { "← Chart of accounts" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      h1(class: "mt-2 text-3xl font-semibold") { @review ? "Review report definition" : (@data["ytd"] ? "YTD account balances" : "Report definitions") }
      p(class: "mt-4 text-sm text-stone-600") { @data["ytd"] ? "Posted account balances using the selected report definition and the book’s fiscal year. Change the through date to rerun the report." : "Map posting accounts to named report lines. Totals reference line codes, for example [REVENUE] - [COSTS]. Each accepted revision preserves its account labels, mappings and formulas. Test balances use whole minor units and are not saved." }
      render Components::Toast.new(message: @message, kind: "alert") if @message
      p(class: "mt-3 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      p(role: "status", class: "mt-4 text-sm text-amber-900") { "The report view is updating. Refresh before editing or previewing." } unless @data["status"] == "ready"
      a(href: url, class: "mt-3 inline-block text-sm text-teal-900 underline") { "Refresh reports" }
      if @check
        a(href: @check, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      ytd_launcher unless @data["selected"] || @review || @editing
      @data.fetch("reports").each do |report|
        div(class: "mt-4 rounded-lg border border-stone-200 bg-white p-4") do
          a(href: url(report_id: report["id"]), class: "font-medium text-teal-900 underline") { "#{report['name']} · Revision #{report['version']}#{report['active'] ? '' : ' · Inactive'}" }
          a(href: url(report_id: report["id"], version: report["version"], ytd: "1", as_of: Date.current.iso8601), class: "ml-4 text-sm text-teal-900 underline") { "YTD balances" }
          details(class: "mt-2 text-sm") do
            summary(class: "cursor-pointer text-teal-900") { "Revision history (#{report.fetch('history', []).length})" }
            report.fetch("history", []).reverse_each do |h|
              p(class: "mt-2") do
                a(href: url(report_id: report["id"], version: h["version"]), class: "text-teal-900 underline") { "#{h['name']} · Revision #{h['version']}#{h['active'] ? '' : ' · Inactive'}" }
                plain " · #{h['accepted_at']} · Actor #{h['actor_identity_id']} · Application #{h['application_id']}"
              end
            end
          end
        end
      end
      if @review
        reviewed
      elsif @editing
        editor(@editing) if @editable
      elsif @data["selected"]
        selected
      elsif @editable
        editor({ "name"=>"", "active"=>true, "expected_version"=>@data["latest_version"], "lines"=>[] })
      end
      a(href: url(new: "1"), class: "mt-6 block text-sm text-teal-900 underline") { "New report" } if @data["selected"] && @editable
    end
  end
  def ytd_launcher
    section(class: "mt-6 rounded-xl border border-stone-200 bg-white p-4", aria: { label: "YTD balances" }) do
      h2(class: "text-xl font-semibold") { "YTD balances" }
      reports = @data.fetch("reports")
      if reports.empty?
        p(class: "mt-2 text-sm text-stone-600") { "Create and accept a report definition below first. YTD balances use its account mappings and formulas to show opening balances, year-to-date movement and closing balances from posted journals." }
      else
        form_with(url: url, method: :get, data: { turbo: false }, class: "mt-3 flex flex-wrap items-end gap-3") do |f|
          f.hidden_field(:ytd, value: "1")
          div do
            f.label(:report_id, "Report definition")
            f.select(:report_id, reports.map { |report| [ "#{report['name']}#{report['active'] ? '' : ' · Inactive'}", report["id"] ] }, {}, class: FIELD)
          end
          div { f.label(:as_of, "Through date"); f.date_field(:as_of, value: Date.current, required: true, class: FIELD) }
          f.submit("Run YTD report", class: BUTTON, disabled: @data["status"] != "ready" || !!@check)
        end
      end
    end
  end

  def line_summary(lines, accounts)
    lookup = accounts.index_by { |a| a["id"] }
    lines.each do |line|
      div(class: "mt-3 rounded-lg border border-stone-200 p-3 text-sm") do
        p(class: "font-medium") { "#{line['position']} · #{line['code']} · #{line['name']} · #{line['kind']}" }
        pre(class: "mt-2 whitespace-pre-wrap break-all") { line["formula"] } if line["kind"] == "total"
        if line["kind"] == "mapping"
          p(class: "mt-2") { "#{line['sign'] == -1 ? 'Subtract' : 'Add'}: #{line.fetch('account_ids').map { |id| lookup[id] ? account_label(lookup[id]) : id }.join('; ')}" }
        end
      end
    end
  end
  def coverage(value, accounts, title)
    return unless value
    lookup = (Array(@data.dig("selected", "definition", "accounts")) + accounts).index_by { |a| a["id"] }
    details(class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm", open: value["unmapped"].any? || value["multiple"].any? || value["empty_lines"].any? || value.fetch("unavailable", []).any?) do
      summary(class: "cursor-pointer font-medium") { "#{title}: #{value['unmapped'].length} unmapped · #{value['multiple'].length} multiply mapped · #{value['empty_lines'].length} empty lines · #{value.fetch('unavailable', []).length} unavailable accounts" }
      p(class: "mt-2") { "Multiple mappings may intentionally repeat an account; totals can then count it more than once. Review this before accepting." } if value["multiple"].any?
      value["unmapped"].each { |a| p(class: "mt-2") { "Unmapped: #{account_label(a)}" } }
      value["multiple"].each { |a| p(class: "mt-2") { "Multiply mapped: #{lookup[a['account_id']] ? account_label(lookup[a['account_id']]) : a['account_id']} → #{a['lines'].join(', ')}" } }
      value.fetch("unavailable", []).each { |id| p(class: "mt-2") { "Mapped account is no longer a current posting account: #{lookup[id] ? account_label(lookup[id]) : id}" } }
      value["empty_lines"].each { |code| p(class: "mt-2") { "Empty mapping line: #{code} (zero)" } }
    end
  end
  def reviewed
    plan = @review.fetch("plan")
    h2(class: "mt-8 text-xl font-semibold") { "#{plan['name']} · #{plan['active'] ? 'Active' : 'Inactive'}" }
    p(class: "mt-2 text-sm") { "Reviewed setup revision #{@review['expected_version']} · Expires #{@review['expires_at']}" }
    if plan["before"]
      details(class: "mt-4") do
        summary(class: "cursor-pointer text-sm text-teal-900") { "Before: #{plan['before']['name']} · #{plan['before']['active'] ? 'Active' : 'Inactive'}" }
        line_summary(plan["before"]["definition"]["lines"], plan["before"]["definition"]["accounts"])
      end
    end
    h3(class: "mt-4 font-semibold") { "After" }
    line_summary(plan["definition"]["lines"], plan["definition"]["accounts"])
    coverage(plan["coverage"], plan["definition"]["accounts"], "Coverage at review")
    if @token
      form_with(url: url, method: :patch, id: "accept-report", data: { turbo: false }) do |f|
        f.hidden_field(:form_token, value: @token)
        f.submit("Accept reviewed report", class: BUTTON)
      end
    end
    a(href: url(review_id: @review["review_id"], edit: "1"), class: "mt-4 block text-sm text-teal-900 underline") { "Continue editing this draft" } if @editable && !@review["accepted_command_id"]
  end
  def editor(values)
    h2(class: "mt-8 text-xl font-semibold") { values["report_id"] ? "Edit report draft" : "New report draft" }
    p(class: "mt-2 text-sm text-stone-600") { "Codes start with a letter and remain reserved to the same line. Mapping lines select accounts and a sign; total lines use formulas; headers use neither. Remove a line from this revision with its Remove checkbox. Changes require review and acceptance." }
    lines = values.fetch("lines", []).dup
    lines << {} if lines.empty? || @extra_line
    lines = lines.first(2000)
    form_with(url: review_tenant_book_reports_path(@tid, @bid), method: :post, id: "report-editor", data: { turbo: false }) do |f|
      f.hidden_field(:expected_version, value: values["expected_version"] || @data["latest_version"])
      f.hidden_field(:report_id, value: values["report_id"])
      f.hidden_field(:expected_report_version, value: values["expected_report_version"])
      div { f.label(:name, "Report name"); f.text_field(:name, value: values["name"], maxlength: 120, required: true, class: FIELD) }
      div { f.label(:active, "Status"); f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: values["active"].to_s }, class: FIELD) }
      lines.each_with_index do |line, index|
        fieldset(class: "mt-5 rounded-xl border border-stone-200 bg-white p-4") do
          legend(class: "px-2 text-sm font-semibold") { "Report line #{index + 1}" }
          input(type: "hidden", name: "lines[#{index}][id]", value: line["id"])
          div(class: "grid gap-3 sm:grid-cols-2") do
            %w[code name position].each do |field|
              div do
                label(for: "line-#{index}-#{field}", class: "text-sm") { field.capitalize }
                input(id: "line-#{index}-#{field}", name: "lines[#{index}][#{field}]", type: field == "position" ? "number" : "text", value: line[field] || (field == "position" ? ((values["lines"] || []).map { |l| l["position"].to_i }.max || 0) + 100 : nil), class: FIELD)
              end
            end
            div do
              label(for: "line-#{index}-kind", class: "text-sm") { "Type" }
              select(id: "line-#{index}-kind", name: "lines[#{index}][kind]", class: FIELD) { %w[mapping total header].each { |kind| option(value: kind, selected: (line["kind"] || "mapping") == kind) { kind.capitalize } } }
            end
            div do
              label(for: "line-#{index}-sign", class: "text-sm") { "Mapping sign" }
              select(id: "line-#{index}-sign", name: "lines[#{index}][sign]", class: FIELD) { option(value: "1", selected: line["sign"] != -1) { "+ Add balances" }; option(value: "-1", selected: line["sign"] == -1) { "− Subtract balances" } }
            end
            div do
              label(for: "line-#{index}-formula", class: "text-sm") { "Total formula" }
              textarea(id: "line-#{index}-formula", name: "lines[#{index}][formula]", maxlength: 2000, class: FIELD) { line["formula"] }
            end
          end
          label(for: "line-#{index}-accounts", class: "mt-3 block text-sm") { "Posting accounts (mapping lines; select multiple with Ctrl/Cmd)" }
          input(type: "hidden", name: "lines[#{index}][account_ids][]", value: "")
          select(id: "line-#{index}-accounts", name: "lines[#{index}][account_ids][]", multiple: true, size: 5, class: FIELD) do
            @data.fetch("accounts").each { |a| option(value: a["id"], selected: Array(line["account_ids"]).include?(a["id"])) { account_label(a) } }
            (Array(line["account_ids"]) - @data.fetch("accounts").map { |a| a["id"] }).each do |id|
              saved = Array(values["saved_accounts"] || @data.dig("selected", "definition", "accounts")).find { |a| a["id"] == id }
              option(value: id, selected: true) { "Unavailable / retired: #{saved ? account_label(saved) : id} — clear before review" }
            end
          end
          label(class: "mt-3 flex items-center gap-2 text-sm") { input(type: "checkbox", name: "lines[#{index}][remove]", value: "1"); plain "Remove this line from the draft" }
        end
      end
      f.submit("Review report", class: BUTTON)
      button(type: "submit", name: "intent", value: "add_line", class: "ml-4 text-sm text-teal-900 underline", formnovalidate: true) { "Add report line" } if lines.length < 2000
    end
  end
  def selected
    report = @data.fetch("selected")
    definition = report.fetch("definition")
    h2(class: "mt-8 text-xl font-semibold") { "#{report['name']} · Revision #{report['version']}#{report['active'] ? '' : ' · Inactive'}" }
    p(class: "mt-2 text-sm text-stone-600") { "Account labels and coverage below are pinned to chart revision #{definition['chart_version']}. Current-chart coverage is shown separately." }
    p(class: "mt-2 text-sm text-stone-600") { "Included YTD definition: one line per posting account in chart order, debit positive and credit negative. Customize it to save your own book-specific mappings and formulas." } if report["builtin"]
    year_to_date(report)
    if @data["ytd"]
      a(href: url(report_id: report["id"], version: report["version"]), class: "mt-4 inline-block text-sm text-teal-900 underline") { "View report definition" }
      coverage(@data["coverage"], definition["accounts"], "Saved revision coverage")
      return
    end
    line_summary(definition["lines"], definition["accounts"])
    coverage(@data["coverage"], definition["accounts"], "Saved revision coverage")
    coverage(@data["current_coverage"], @data["accounts"], "Current chart coverage")
    a(href: url(report_id: report["id"], edit: "1"), class: "mt-4 block text-sm text-teal-900 underline") { report["builtin"] ? "Customize YTD definition" : "Edit current report" } if @editable
    if @data["status"] == "ready" && !@check
      h3(class: "mt-6 text-lg font-semibold") { "Test this report revision" }
      form_with(url: preview_tenant_book_reports_path(@tid, @bid), method: :post, id: "report-preview", data: { turbo: false }) do |f|
        f.hidden_field(:report_id, value: report["id"])
        f.hidden_field(:report_version, value: report["version"])
        definition["accounts"].each do |account|
          div(class: "mt-3 grid gap-2 sm:grid-cols-2") do
            label(for: "report-balance-#{account['id']}", class: "text-sm") { account_label(account) }
            input(id: "report-balance-#{account['id']}", name: "balances[#{account['id']}]", value: @balances[account["id"]], type: "number", step: "1", min: -9_000_000_000_000, max: 9_000_000_000_000, class: FIELD)
          end
        end
        p(class: "mt-3 text-sm text-stone-600") { "Blank means unknown; enter 0 explicitly for zero. Nested totals stay exact; displayed results round to the nearest minor unit with half ties away from zero. These are test results, not ledger balances." }
        f.submit("Preview report", class: BUTTON)
      end
    end
    Array(@data["results"]).each do |result|
      line = definition["lines"].find { |l| l["id"] == result["account_id"] }
      div(class: "mt-4 rounded-lg border border-stone-200 bg-white p-4", data: { report_result: line["code"] }) do
        h3(class: "font-semibold") { "#{line['code']} · #{line['name']}" }
        if result["status"] == "ok"
          p(class: "mt-2 font-semibold text-teal-900") { "Result: #{result['amount_minor']} minor units" }
          p(class: "mt-1 text-xs text-stone-500") { "Exact: #{result['exact']['numerator']}/#{result['exact']['denominator']}" }
          details(class: "mt-3 text-sm") do
            summary(class: "cursor-pointer") { "Underlying accounts (#{result.fetch('inputs').length})" }
            result.fetch("inputs").each { |a| p(class: "mt-2") { "#{account_label(a)}: #{a['balance_minor']} minor units" } }
            result.fetch("references", []).each { |r| p(class: "mt-2") { "[#{r['reference']}] → #{r['name']}: #{r['amount_minor']} minor units" } }
          end
        else
          related = definition["accounts"].find { |a| a["id"] == result["related_account_id"] }
          p(role: "status", class: "mt-2 text-sm text-amber-900") { "#{Views::FormulaPreviews::Show::ERRORS.fetch(result['error'], 'This report line could not be calculated.')}#{related ? " Account: #{account_label(related)}" : ''}" }
        end
      end
    end
  end
  def year_to_date(report)
    h3(class: "mt-6 text-xl font-semibold") { "Year-to-date account balances" }
    form_with(url: url, method: :get, data: { turbo: false }, class: "mt-3 flex items-end gap-3") do |f|
      f.hidden_field(:report_id, value: report["id"])
      f.hidden_field(:version, value: report["version"])
      f.hidden_field(:ytd, value: "1")
      div { f.label(:as_of, "Through date"); f.date_field(:as_of, value: @data.dig("ytd", "as_of") || Date.current, required: true, class: FIELD) }
      f.submit("Run YTD report", class: BUTTON)
    end
    return unless (data = @data["ytd"])
    p(class: "mt-3 text-sm text-stone-600") { "#{data['start_date']} – #{data['as_of']} · #{data['currency']} · #{data['journal_count']} posted journals in period · Debit positive, credit negative; definition signs apply. Opening includes all earlier postings. Drafts are excluded." }
    div(class: "mt-4 overflow-x-auto") do
      table(class: "w-full text-sm") do
        thead { tr { %w[Code Name Opening YTD Closing].each { |label| th(class: "p-2 text-right first:text-left") { label } } } }
        tbody do
          report.fetch("definition").fetch("lines").sort_by { |line| line["position"] }.each do |line|
            tr(class: "border-t border-stone-200") do
              td(class: "p-2") { line["code"] }
              td(class: "p-2") { line["name"] }
              %w[opening movement closing].each do |column|
                result = data.fetch(column).find { |r| r["account_id"] == line["id"] }
                td(class: "p-2 text-right tabular-nums") do
                  if line["kind"] == "header"
                    plain ""
                  elsif result && result["status"] == "ok"
                    plain number_with_precision(BigDecimal(result.fetch("amount_minor").to_s) / 100, precision: 2, delimiter: ".", separator: ",")
                  else
                    plain "Cannot calculate"
                  end
                end
              end
            end
          end
        end
      end
    end
    details(class: "mt-4 text-sm") do
      summary(class: "cursor-pointer text-teal-900") { "Underlying account closing balances" }
      report.fetch("definition").fetch("accounts").each do |account|
        amount = data.fetch("balances", {}).fetch(account["id"], 0)
        p(class: "mt-2") { "#{account_label(account)}: #{number_with_precision(BigDecimal(amount.to_s) / 100, precision: 2, delimiter: '.', separator: ',')} #{data['currency']}" }
      end
    end
  end

  def account_label(account) = "#{account['number']} · #{account['name']}#{account['active'] ? '' : ' · Inactive'}"
end
