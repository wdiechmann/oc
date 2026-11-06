class Components::Periods < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(data:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil)
    @data, @token, @draft, @message, @check, @retry = data, token, draft, message, check_url, retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @ready = data["status"] == "ready" && !check_url
    @configure = @ready && data.dig("permissions", "configure")
  end
  def view_template
    div(id: "vera-book-content", class: "break-words") do
      a(href: tenant_book_setup_path(@tid, @bid), class: "text-sm font-medium text-teal-900 hover:underline") { "← Roles and occasions" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      div(class: "mt-3 flex flex-wrap items-end justify-between gap-4") do
        h1(class: "text-3xl font-semibold tracking-tight") { "Accounting periods" }
        a(href: tenant_book_chart_path(@tid, @bid), class: "text-sm font-medium text-teal-900 hover:underline") { "Chart of accounts" }
      end
      p(class: "mt-4 max-w-3xl text-sm leading-relaxed text-stone-600") { "Periods use inclusive dates in #{@data.fetch('timezone')}. Draft dates can be corrected until the first opening. Reopening a closed period requires separate permission and a recorded reason." }
      if @data["accounting_authority"] == "external"
        p(class: "mt-4 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm") { "These are local preparation controls. They do not change periods in your external accounting system." }
      end
      render Components::Toast.new(message: @message, kind: "alert") if @message
      if @check
        a(href: @check, data: { turbo_stream: true }, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      unless @data["status"] == "ready"
        p(role: "status", class: "mt-5 rounded-lg bg-amber-50 p-4 text-sm") { "The period view is updating. Refresh to see the accepted revision before making another change." }
      end
      p(class: "mt-4 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      a(href: tenant_book_periods_path(@tid, @bid), class: "mt-3 inline-block text-sm font-medium text-teal-900 hover:underline") { "Refresh periods" }
      if @draft && (!@configure || !draft_renderable?)
        submitted_draft
      end
      section(aria_label: "Accounting periods", class: "mt-7 space-y-4") do
        @data.fetch("periods").each { |period| period_card(period) }
        p(class: "rounded-xl border border-stone-200 bg-white p-5 text-sm text-stone-500") { "No accounting periods have been created for this book." } if @data.fetch("periods").empty?
      end
      if @configure
        h2(class: "mt-9 text-xl font-semibold") { "Create a draft period" }
        date_form(nil)
      else
        p(class: "mt-6 text-sm text-stone-500") { "An explicitly assigned configuration steward can maintain periods." } unless @data.dig("permissions", "configure")
      end
    end
  end
  private
  def draft_renderable?
    return true if @draft[:action] == "period_create"
    period = @data.fetch("periods").find { |p| p["id"] == @draft.dig(:attrs, :period_id) }
    return false unless period
    (@draft[:action] == "period_revise" && period["status"] == "draft") || (@draft[:action] == "period_reopen" && period["status"] == "closed" && @data.dig("permissions", "reopen"))
  end
  def matching_draft(action, id)
    @draft && @draft[:action] == action && @draft.dig(:attrs, :period_id) == id ? @draft.fetch(:attrs) : nil
  end
  def hidden(f, action, period = nil)
    f.hidden_field(:form_token, value: @token.call(action, period && period.fetch("id")))
    f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
    f.hidden_field(:expected_period_version, value: period.fetch("version")) if period
  end
  def field(f, name, title)
    f.label(name, title, class: "block text-sm font-medium")
    yield
  end
  def date_form(period)
    action = period ? "period_revise" : "period_create"
    draft = matching_draft(action, period && period["id"])
    values = draft ? draft.stringify_keys : period || {}
    form_with(url: tenant_book_periods_path(@tid, @bid), method: :patch, namespace: "#{action}-#{period && period['id'] || 'new'}", id: "#{action}-#{period && period['id'] || 'new'}", class: "mt-4 rounded-xl border border-stone-200 bg-white p-5") do |f|
      hidden(f, action, period)
      p(class: "mb-4 text-sm font-semibold text-amber-900") { "Your submitted draft — compare with the accepted period below" } if draft
      div(class: "grid gap-4 md:grid-cols-3") do
        div { field(f, :name, "Period name") { f.text_field(:name, value: values["name"], required: true, maxlength: 120, class: FIELD) } }
        div { field(f, :start_date, "Start date (inclusive)") { f.date_field(:start_date, value: values["start_date"], required: true, class: FIELD) } }
        div { field(f, :end_date, "End date (inclusive)") { f.date_field(:end_date, value: values["end_date"], required: true, class: FIELD) } }
      end
      f.submit(draft ? "Reapply period draft" : period ? "Save draft dates" : "Create draft period", class: BUTTON)
      a(href: tenant_book_periods_path(@tid, @bid), class: "ml-4 text-sm font-medium text-teal-900 hover:underline") { "Cancel" }
    end
  end
  def period_card(period)
    div(id: "period-#{period.fetch('id')}", class: "rounded-xl border border-stone-200 bg-white p-5 sm:p-6") do
      draft = matching_draft("period_revise", period["id"])
      date_form(period) if @configure && draft && period["status"] == "draft"
      div(class: "flex flex-wrap items-start justify-between gap-3") do
        div do
          h2(class: "text-xl font-semibold") { period.fetch("name") }
          p(class: "mt-2 text-sm text-stone-600") { "#{period['start_date']} → #{period['end_date']} · Revision #{period['version']}" }
        end
        span(class: "rounded-full border border-stone-200 bg-stone-50 px-3 py-1 text-xs font-semibold uppercase tracking-wider") { period.fetch("status").capitalize }
      end
      if @configure
        case period["status"]
        when "draft"
          unless draft
            details(class: "mt-4") do
              summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Correct draft dates" }
              date_form(period)
            end
          end
          transition_form("period_open", period, "Open period") unless draft
        when "open"
          transition_form("period_close", period, "Close period")
        when "closed"
          if @data.dig("permissions", "reopen")
            transition_form("period_reopen", period, "Reopen period")
          else
            p(class: "mt-4 text-sm text-stone-500") { "Reopening permission has not been granted. A tenant administrator can assign it to a current book steward under Roles and occasions." }
          end
        end
      end
      history(period)
    end
  end
  def transition_form(action, period, label)
    draft = matching_draft(action, period["id"])
    form_with(url: tenant_book_periods_path(@tid, @bid), method: :patch, namespace: "#{action}-#{period['id']}", id: "#{action}-#{period['id']}", class: "mt-4") do |f|
      hidden(f, action, period)
      if action == "period_reopen"
        field(f, :reason, "Reason for reopening") { f.text_area(:reason, value: draft && draft[:reason], required: true, maxlength: 500, rows: 2, class: FIELD) }
      end
      f.submit(label, class: BUTTON)
    end
  end
  def history(period)
    details(class: "mt-5 border-t border-stone-200 pt-4") do
      summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Period history (#{period.fetch('history', []).length})" }
      ol(class: "mt-3 space-y-3") do
        period.fetch("history", []).reverse_each do |fact|
          li(class: "rounded-lg bg-stone-50 p-3 text-sm") do
            p(class: "font-medium") { "#{fact['event_type'].to_s.delete_prefix('Period')} · #{fact['status']} · Revision #{fact['version']}" }
            p(class: "mt-1 text-xs text-stone-600") { "#{fact['name']} · #{fact['start_date']} → #{fact['end_date']}" }
            p(class: "mt-1 text-xs break-words text-stone-500") { "#{fact['accepted_at']} · Actor #{fact['actor_identity_id']} · Application #{fact['application_id']}" }
            p(class: "mt-2") { "Reason: #{fact['reason']}" } if fact["reason"].present?
          end
        end
      end
    end
  end
  def submitted_draft
    h2(class: "mt-6 text-lg font-semibold") { "Your submitted draft" }
    pre(class: "mt-3 whitespace-pre-wrap break-words rounded-lg bg-amber-50 p-4 text-sm") { @draft.fetch(:attrs).except(:expected_version, :expected_period_version).map { |k, v| "#{k}: #{v}" }.join("\n") }
  end
end
