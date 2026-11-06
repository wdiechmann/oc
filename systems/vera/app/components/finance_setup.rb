class Components::FinanceSetup < Components::Base
  include Phlex::Rails::Helpers::FormWith
  BUTTON = Views::Base::BUTTON
  def initialize(data:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil, query: "")
    @data, @token, @draft, @message, @check, @query = data, token, draft, message, check_url, query
    @retry = retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @ready = data["status"] == "ready" && !check_url
  end
  def view_template
    div(id: "vera-book-content") do
      a(href: root_path, class: "text-sm font-medium text-teal-900 hover:underline") { "← Your workspaces" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      header(class: "mt-3 flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-4xl font-semibold tracking-tight") { "Book configuration" }
        render Components::ContextMenu.new(id: "setup-header-actions", label: "Book configuration actions") do
          a(href: tenant_books_path(@tid), role: "menuitem", class: "vera-menu-item") { "Back to books" }
          a(href: tenant_book_chart_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "Open chart of accounts" }
          a(href: tenant_book_catalogues_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "VAT and categories" }
          a(href: tenant_book_periods_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "Accounting periods" }
        end
      end
      p(class: "mt-4 max-w-3xl leading-relaxed text-stone-600") { "Assign stewards and link occasions. Open the chart of accounts to maintain its rows. Roles apply to this book only. Permission to reopen closed periods is granted separately." }
      render Components::Toast.new(message: @message, kind: "alert") if @message
      if @check
        a(href: @check, data: { turbo_stream: true }, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
        p(class: "mt-4 text-sm") { "Resolve the previous save before submitting another change." }
      end
      unless @data["status"] == "ready"
        p(role: "status", class: "mt-5 rounded-lg border border-amber-200 bg-amber-50 p-4") { "The setup view is updating. Editing resumes when the accepted revision is projected." }
      end
      p(class: "mt-4 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      a(href: tenant_book_setup_path(@tid, @bid), class: "mt-4 inline-block text-sm font-medium text-teal-900 hover:underline") { "Refresh setup" }
      if @draft && (!@ready || !%w[steward reopening_authority binding].include?(@draft[:action]))
        h2(class: "mt-6 text-lg font-semibold") { "Your submitted draft" }
        dl(class: "mt-3 rounded-lg border border-amber-200 p-4") do
          @draft.fetch(:attrs).each { |key, value| div { dt(class: "text-xs text-stone-500") { key.to_s.humanize }; dd { value.to_s } } }
        end
      end
      stewards if @data.dig("permissions", "assign_stewards")
      bindings
    end
  end
  private
  def stewards
    section(class: "mt-10", aria_label: "Finance configuration stewards") do
      header(class: "flex flex-wrap items-center justify-between gap-3") do
        h2(class: "text-2xl font-semibold") { "Configuration stewards" }
        div(class: "flex flex-wrap items-center gap-2") do
          dialog_action("steward", "Steward assignment", @ready)
          dialog_action("reopening_authority", "Permission to reopen periods", @ready && @data.fetch("stewards").any?)
        end
      end
      p(class: "mt-3 text-sm text-stone-600") { "Tenant administration lets you assign this role explicitly, including to yourself. It does not grant configuration access automatically." }
      @data.fetch("stewards").each do |s|
        label = @data.fetch("candidates").find { |c| c["identity_id"] == s["identity_id"] }&.fetch("label") || s.fetch("identity_id")
        p(class: "mt-3 text-sm") { "#{label} · Reopen periods: #{s['can_reopen_periods'] ? 'Allowed' : 'Not granted'}" }
      end
    end
  end
  def bindings
    section(class: "mt-10", aria_label: "Occasion bindings") do
      header(class: "flex flex-wrap items-center justify-between gap-3") do
        h2(class: "text-2xl font-semibold") { "Linked occasions" }
        dialog_action("binding", "Link occasion", @ready) if @data.dig("permissions", "configure")
      end
      @data.fetch("bindings").each do |b|
        name = @data.fetch("occasions").find { |o| o["occasion_id"] == b["occasion_id"] }&.fetch("name") || b.fetch("occasion_id")
        p(class: "mt-3 text-sm") { name }
      end
      p(class: "mt-3 text-sm text-stone-500") { "No occasions are linked to this book." } if @data.fetch("bindings").empty?
    end
  end
  def dialog_action(kind, label, enabled)
    styles = "rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm font-medium text-teal-900"
    if enabled
      a(href: assignment_dialog_tenant_book_setup_path(@tid, @bid, kind: kind), data: { turbo_stream: true }, class: styles) { label }
    else
      button(type: "button", disabled: true, class: "#{styles} opacity-50") { label }
    end
  end
end
