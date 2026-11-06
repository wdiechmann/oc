class Components::Chart < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :coa_editor
  def initialize(data:, collection:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil, query: "", focus_id: nil, focus_edge: "")
    @data, @collection, @token, @draft, @message, @check, @retry, @query, @focus, @edge = data, collection, token, draft, message, check_url, retry_url, query, focus_id, focus_edge
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    div(id: "vera-book-content") do
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      header(class: "mt-2 flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-3xl font-semibold tracking-tight") { @data["retired"] ? "Retired accounts" : "Chart of accounts" }
        chart_menu
      end
      p(class: "mt-3 text-sm text-stone-600") { "Retired accounts are read-only history. Their original positions, numbers, identities and references are preserved." } if @data["retired"]
      unless @data["catalogues_initialized"]
        p(class: "mt-4 rounded-lg bg-amber-50 p-3 text-sm") { "Initialize this book’s VAT/category catalogues before editing the chart. Existing selections will be preserved and bound to stable entries." }
      end
      p(class: "mt-4 text-sm text-stone-600", id: "coa-help") { @data["retired"] ? "↑/↓ move · Home/End first/last · PgUp/PgDn page. Retired rows are read-only." : "↑/↓ move · Home/End first/last · PgUp/PgDn page · Enter edit/save · Escape cancel. Tab moves between fields while editing." }
      render Components::Toast.new(message: @message, kind: "alert") if @message
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
        p(id: "coa-status", hidden: true)
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
  def chart_menu
    render Components::ContextMenu.new(id: "chart-header-actions", label: "Chart actions") do
      menu_link(tenant_book_chart_path(@tid, @bid, focus_id: @focus, retired: @data["retired"] ? "1" : nil), "Refresh chart")
      menu_link(tenant_book_chart_path(@tid, @bid, retired: @data["retired"] ? nil : "1"), @data["retired"] ? "Current chart" : "Retired accounts")
      menu_link(tenant_book_setup_path(@tid, @bid), "Roles and occasions")
      menu_link(tenant_book_periods_path(@tid, @bid), "Accounting periods")
      menu_link(tenant_book_vat_rules_path(@tid, @bid), "VAT code settings")
      menu_link(tenant_book_catalogues_path(@tid, @bid), "Categories and code names")
      unless @data["retired"]
        hr(role: "separator", class: "my-1 border-stone-200")
        if @data["status"] == "ready" && !@check
          menu_link(tenant_book_journals_path(@tid, @bid), "Journals")
          menu_link(tenant_book_reports_path(@tid, @bid), "Report definitions")
          menu_link(tenant_book_formula_preview_path(@tid, @bid), "Formula preview")
        end
        menu_link(tenant_book_chart_order_path(@tid, @bid), "Reorder / rebalance") if @data.dig("permissions", "configure") && @data["status"] == "ready" && @data["catalogues_initialized"] && !@check
        hr(role: "separator", class: "my-1 border-stone-200")
        menu_link(tenant_book_chart_import_path(@tid, @bid), "Import CSV") if @data.dig("permissions", "configure")
        menu_link(export_tenant_book_chart_import_path(@tid, @bid, source_version: @data["source_version"]), "Export accepted chart", export: true)
        menu_link(export_tenant_book_chart_import_path(@tid, @bid, q: @query, source_version: @data["source_version"]), "Export filtered chart", export: true) if @query.present?
        menu_link(template_tenant_book_chart_import_path(@tid, @bid), "CSV template", export: true)
      end
    end
  end
  def menu_link(href, text, export: false)
    a(href: href, role: "menuitem", class: "vera-menu-item", data: export ? { turbo: false, chart_export: true } : {}) { text }
  end
end
