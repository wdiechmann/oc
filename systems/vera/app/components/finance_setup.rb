class Components::FinanceSetup < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = Views::Base::FIELD
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
      h1(class: "mt-3 text-4xl font-semibold tracking-tight") { "Book configuration" }
      p(class: "mt-4 max-w-3xl leading-relaxed text-stone-600") { "Assign stewards and link occasions. Open the chart of accounts to maintain its rows. Setup permissions apply to this book only and grant no journal approval, posting or payment authority." }
      p(role: "alert", class: "mt-5 rounded-lg border border-amber-200 bg-amber-50 p-4") { @message } if @message
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
      if @draft && (!@ready || !@draft[:action].start_with?("account_"))
        h2(class: "mt-6 text-lg font-semibold") { "Your submitted draft" }
        dl(class: "mt-3 rounded-lg border border-amber-200 p-4") do
          @draft.fetch(:attrs).each { |key, value| div { dt(class: "text-xs text-stone-500") { key.to_s.humanize }; dd { value.to_s } } }
        end
      end
      stewards if @data.dig("permissions", "assign_stewards")
      bindings
      accounts
      a(href: tenant_book_periods_path(@tid, @bid), class: "ml-4 inline-block text-sm font-medium text-teal-900 hover:underline") { "Accounting periods" }
    end
  end
  private
  def setup_form(action, account_id: nil, &block)
    form_with(url: tenant_book_setup_path(@tid, @bid), method: :patch, namespace: "#{action}-#{account_id || 'new'}", id: "setup-#{action}-#{account_id || 'new'}", class: "mt-4 rounded-xl border border-stone-200 bg-white p-5", &block)
  end
  def hidden(f, action, account_id = nil)
    f.hidden_field(:form_token, value: @token.call(action, account_id))
    f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
  end
  def field(f, name, label)
    f.label(name, label, class: "mt-3 block text-sm font-medium")
    yield
  end
  def stewards
    section(class: "mt-10 max-w-3xl", aria_label: "Finance configuration stewards") do
      h2(class: "text-2xl font-semibold") { "Configuration stewards" }
      p(class: "mt-3 text-sm text-stone-600") { "Tenant administration lets you assign this role explicitly, including to yourself. It does not grant configuration access automatically." }
      @data.fetch("stewards").each do |s|
        label = @data.fetch("candidates").find { |c| c["identity_id"] == s["identity_id"] }&.fetch("label") || s.fetch("identity_id")
        p(class: "mt-3 text-sm") { "#{label} · Reopen periods: #{s['can_reopen_periods'] ? 'Allowed' : 'Not granted'}" }
      end
      return unless @ready
      setup_form("steward") do |f|
        hidden(f, "steward")
        choices = @data.fetch("candidates").map { |c| [ c.fetch("label"), c.fetch("identity_id") ] }
        choices += @data.fetch("stewards").reject { |s| choices.any? { |c| c.last == s["identity_id"] } }.map { |s| [ s.fetch("identity_id"), s.fetch("identity_id") ] }
        field(f, :identity_id, "Existing identity") { f.select(:identity_id, choices, {}, class: FIELD, required: true) }
        field(f, :active, "Role action") { f.select(:active, [ [ "Assign steward", "true" ], [ "Revoke steward", "false" ] ], {}, class: FIELD) }
        f.submit("Save steward assignment", class: BUTTON)
      end
      unless @data.fetch("stewards").empty?
        setup_form("reopening_authority") do |f|
          hidden(f, "reopening_authority")
          p(class: "text-sm font-medium") { "Separate permission to reopen closed periods" }
          choices = @data.fetch("stewards").map do |s|
            candidate = @data.fetch("candidates").find { |c| c["identity_id"] == s["identity_id"] }
            [ candidate ? candidate.fetch("label") : s.fetch("identity_id"), s.fetch("identity_id") ]
          end
          field(f, :identity_id, "Assigned steward") { f.select(:identity_id, choices, {}, required: true, class: FIELD) }
          field(f, :allow, "Reopening permission") { f.select(:allow, [ [ "Grant reopening permission", "true" ], [ "Revoke reopening permission", "false" ] ], {}, class: FIELD) }
          f.submit("Save reopening permission", class: BUTTON)
        end
      end
    end
  end
  def bindings
    section(class: "mt-10 max-w-3xl", aria_label: "Occasion bindings") do
      h2(class: "text-2xl font-semibold") { "Linked occasions" }
      @data.fetch("bindings").each do |b|
        name = @data.fetch("occasions").find { |o| o["occasion_id"] == b["occasion_id"] }&.fetch("name") || b.fetch("occasion_id")
        p(class: "mt-3 text-sm") { name }
      end
      p(class: "mt-3 text-sm text-stone-500") { "No occasions are linked to this book." } if @data.fetch("bindings").empty?
      return unless @ready && @data.dig("permissions", "configure")
      setup_form("binding") do |f|
        hidden(f, "binding")
        field(f, :occasion_id, "Occasion") { f.select(:occasion_id, @data.fetch("occasions").map { |o| [ o.fetch("name"), o.fetch("occasion_id") ] }, {}, required: true, class: FIELD) }
        field(f, :active, "Binding action") { f.select(:active, [ [ "Link to this book", "true" ], [ "Unlink from this book", "false" ] ], {}, class: FIELD) }
        p(class: "mt-3 text-xs text-stone-500") { "Each occasion has one applicable book. Its current book’s steward must unlink it before reassignment." }
        f.submit("Save occasion binding", class: BUTTON)
      end
    end
  end
  def accounts
    a(href: tenant_book_chart_path(@tid, @bid), class: BUTTON) { "Open chart of accounts" }
  end
end
