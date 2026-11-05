class Components::Chart < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :coa_editor
  def initialize(data:, collection:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil, query: "", focus_id: nil, focus_edge: "")
    @data, @collection, @token, @draft, @message, @check, @retry, @query, @focus, @edge = data, collection, token, draft, message, check_url, retry_url, query, focus_id, focus_edge
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    div(id: "vera-book-content") do
      a(href: tenant_book_setup_path(@tid, @bid), class: "text-sm font-medium text-teal-900 hover:underline") { "← Roles and occasions" }
      div(class: "mt-6 flex flex-wrap items-end justify-between gap-4") do
        div do
          p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
          h1(class: "mt-2 text-3xl font-semibold tracking-tight") { @data["retired"] ? "Retired accounts" : "Chart of accounts" }
        end
        a(href: tenant_book_chart_path(@tid, @bid, focus_id: @focus, retired: @data["retired"] ? "1" : nil), class: "text-sm font-medium text-teal-900 hover:underline") { "Refresh chart" }
      end
      a(href: tenant_book_chart_path(@tid, @bid, retired: @data["retired"] ? nil : "1"), class: "mt-3 mr-4 inline-block text-sm font-medium text-teal-900 hover:underline") { @data["retired"] ? "Current chart" : "Retired accounts" }
      p(class: "mt-3 text-sm text-stone-600") { "Retired accounts are read-only history. Their original positions, numbers, identities and references are preserved." } if @data["retired"]
      a(href: tenant_book_periods_path(@tid, @bid), class: "mt-3 inline-block text-sm font-medium text-teal-900 hover:underline") { "Accounting periods" }
      a(href: tenant_book_vat_rules_path(@tid, @bid), class: "ml-4 text-sm font-medium text-teal-900 hover:underline") { "VAT code settings" }
      a(href: tenant_book_catalogues_path(@tid, @bid), class: "ml-4 text-sm font-medium text-teal-900 hover:underline") { "Categories and code names" }
      unless @data["catalogues_initialized"]
        p(class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm") { "Initialize this book’s VAT/category catalogues before editing the chart. Existing selections will be preserved and bound to stable entries." }
      end
      p(class: "mt-4 text-sm text-stone-600", id: "coa-help") { @data["retired"] ? "↑/↓ move · Home/End first/last · PgUp/PgDn page. Retired rows are read-only." : "↑/↓ move · Home/End first/last · PgUp/PgDn page · Enter edit/save · Escape cancel. Tab moves between fields while editing." }
      p(role: "alert", class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm") { @message } if @message
      if @check
        a(href: @check, data: { turbo_stream: true }, class: Views::Base::BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: Views::Base::BUTTON) } if @retry
      end
      unless @data["status"] == "ready"
        p(role: "status", class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm") { "The chart view is updating. Editing resumes when the accepted revision is projected." }
      end
      p(class: "mt-3 text-xs text-stone-500") { "#{@collection.total_entries} rows · View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      form_with(url: tenant_book_chart_path(@tid, @bid), method: :get, class: "my-5 flex max-w-lg gap-2") do |f|
        f.hidden_field(:retired, value: "1") if @data["retired"]
        f.label(:q, "Find an account", class: "sr-only")
        f.search_field(:q, value: @query, placeholder: "Find by number or name", class: "min-w-0 grow rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm")
        f.submit("Search", class: "cursor-pointer rounded-lg bg-teal-950 px-4 py-2 text-sm font-medium text-white")
      end
      coa_editor(data: { page: @collection.current_page.to_i, pages: @collection.total_pages, source_version: @data.fetch("source_version"), chart_url: tenant_book_chart_path(@tid, @bid, q: @query.presence, retired: @data["retired"] ? "1" : nil), focus_id: @focus, focus_edge: @edge, pending: (@data["status"] != "ready").to_s }, class: "block", aria_describedby: "coa-help") do
        unless @data["retired"]
        div(class: "mb-4 flex flex-wrap gap-4 text-sm text-teal-900 underline") do
          a(href: export_tenant_book_chart_import_path(@tid, @bid, source_version: @data["source_version"]), data: { turbo: false, chart_export: true }) { "Export accepted chart" }
          a(href: export_tenant_book_chart_import_path(@tid, @bid, q: @query, source_version: @data["source_version"]), data: { turbo: false, chart_export: true }) { "Export filtered chart" } if @query.present?
          a(href: template_tenant_book_chart_import_path(@tid, @bid), data: { turbo: false, chart_export: true }) { "CSV template" }
          a(href: tenant_book_journals_path(@tid, @bid)) { "Journal drafts" } if @data["status"] == "ready" && !@check
          a(href: tenant_book_reports_path(@tid, @bid)) { "Report definitions" } if @data["status"] == "ready" && !@check
          a(href: tenant_book_formula_preview_path(@tid, @bid)) { "Formula preview" } if @data["status"] == "ready" && !@check
          a(href: tenant_book_chart_order_path(@tid, @bid)) { "Reorder / rebalance" } if @data.dig("permissions", "configure") && @data["status"] == "ready" && @data["catalogues_initialized"] && !@check
          a(href: tenant_book_chart_import_path(@tid, @bid)) { "Import CSV" } if @data.dig("permissions", "configure")
        end
        end
        p(id: "coa-status", role: "status", aria_live: "polite", class: "mb-3 text-sm text-amber-900")
        div(class: "coa-scroll", tabindex: "-1") do
          div(class: "coa-grid", role: "table", aria_label: "Chart of accounts") do
            div(class: "coa-columns coa-heading", role: "row") do
              %w[Type Number Name VAT Category Position Formula Actions].each { |label| div(role: "columnheader") { label } }
            end
            div(id: "coa-rows", role: "rowgroup") do
              @collection.each { |account| render Components::ChartRow.new(data: @data, account: account, token: @token, draft: @draft, locked: !!@check) }
            end
            if @collection.empty?
              p(class: "p-5 text-sm text-stone-500") { "No accounts match this chart." }
            end
            if @data.dig("permissions", "configure") && @data["catalogues_initialized"] == true && @data["status"] == "ready" && !@check
              render Components::ChartRow.new(data: @data, account: nil, token: @token, draft: @draft)
            end
          end
        end
        render Components::ChartPagination.new(data: @data, collection: @collection, query: @query)
        missing_draft_account = @draft && @draft[:action] == "account_revise" && @collection.none? { |row| row["id"] == @draft[:attrs][:account_id] }
        if @draft && (@data["status"] != "ready" || missing_draft_account)
          p(class: "mt-4 text-sm font-medium") { missing_draft_account ? "This account is no longer in the current chart. Your submitted draft is preserved below." : "Your submitted draft (waiting for the accepted chart)" }
          pre(class: "mt-2 whitespace-pre-wrap rounded-lg bg-amber-50 p-4 text-sm") { @draft.fetch(:attrs).except(:expected_version, :expected_account_version).map { |k, v| "#{k}: #{v}" }.join("\n") }
        end
      end
    end
  end
end
