class Components::MonitoringList < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(tenant_id:, kind:, filters:, data:)
    @tenant, @kind, @filters, @data = tenant_id, kind, filters, data
  end

  def view_template
    div(class: "flex flex-wrap items-center justify-between gap-4") do
      h1(class: "text-3xl font-semibold tracking-tight") { "Monitoring" }
      a(href: monitoring_path, class: "text-sm font-semibold text-emerald-800 underline") { "Change scope" }
    end
    p(class: "mt-3 break-all text-xs text-stone-500") { "Tenant #{@tenant}#{" · Occasion #{@filters['occasion_id']}" if @filters['occasion_id']}" }
    form_with(url: tenant_monitoring_path(@tenant), method: :get, data: { turbo_stream: true }, class: "mt-7 grid gap-4 rounded-xl border border-stone-200 bg-white p-5 sm:grid-cols-3") do |f|
      f.hidden_field(:occasion_id, value: @filters["occasion_id"]) if @filters["occasion_id"]
      select_field(f, :view, "List", [ [ "Issues", "issues" ], [ "Observations", "observations" ] ], @kind)
      select_field(f, :severity, "Severity", [ [ "All levels", "" ], [ "Critical", "critical" ], [ "Error", "error" ], [ "Warning", "warning" ], [ "Info", "info" ] ], @filters["severity"])
      select_field(f, :state, "Issue state", [ [ "All states", "" ], [ "Open", "open" ], [ "Acknowledged", "acknowledged" ], [ "Resolved", "resolved" ] ], @filters["state"])
      { code: "Code", application: "Application", correlation_id: "Support / correlation reference" }.each do |key, label|
        div { f.label(key, label, class: "text-xs font-medium"); f.text_field(key, value: @filters[key.to_s], maxlength: 128, class: Views::Base::FIELD) }
      end
      f.submit("Apply filters", class: Views::Base::BUTTON)
    end
    freshness = @data.fetch("freshness", {})
    p(class: "mt-5 text-sm text-stone-500", data_monitoring_freshness: true) { "Checked #{freshness['checked_at'] || 'unknown'} · #{freshness['pending_events'] || 'unknown'} pending events#{" · Oldest pending: #{freshness['oldest_pending_at']}" if freshness['oldest_pending_at']}" }
    p(class: "mt-2 text-xs text-stone-500") { "Views may lag accepted facts. Informational outcomes are not necessarily incidents. Rows are ordered by their first appearance in this view." }
    a(href: tenant_monitoring_path(@tenant, **@filters.merge("view" => @kind).except("cursor", "cutoff")), class: "mt-4 inline-block font-semibold text-emerald-800 underline", data: { turbo_stream: true }) { "Refresh list" }
    items = @data.fetch("items", [])
    if items.empty?
      p(class: "mt-8 rounded-xl border border-stone-200 bg-white p-7") { "No matching records in this view. Check freshness before concluding that no issues exist." }
    else
      ul(class: "mt-6 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-white px-5", aria_label: "Monitoring records") do
        items.each do |row|
          data = row.fetch("data", {})
          li(class: "grid gap-3 py-5 md:grid-cols-[6rem_1fr_5rem_8rem]") do
            span(class: "text-sm font-bold uppercase") { data["severity"] }
            div(class: "min-w-0") do
              a(href: tenant_monitoring_issue_path(@tenant, row.fetch("issue_id"), occasion_id: @filters["occasion_id"]), class: "break-words font-semibold text-emerald-900 underline") { data["safe_message"] || data["code"] }
              p(class: "mt-1 break-all text-xs text-stone-500") { "#{data['application']} · #{data['code']} · #{data['last_seen'] || data['received_at']}" }
              p(class: "mt-1 break-all text-xs") { "Owner: #{data['owner_identity_id'] || 'Unassigned'}" } if @kind == "issues"
            end
            span(class: "text-sm") { "× #{data['count'] || data['occurrence_count']}" }
            span(class: "text-sm") { data["state"] || data["outcome"] }
          end
        end
      end
    end
    if @data["next_cursor"]
      a(href: tenant_monitoring_path(@tenant, **@filters.merge("view" => @kind, "cursor" => @data["next_cursor"])), class: "mt-6 inline-block font-semibold text-emerald-800 underline", data: { turbo_stream: true }) { "Next 50 records →" }
    end
  end

  private
  def select_field(form, key, label, choices, selected)
    div { form.label(key, label, class: "text-xs font-medium"); form.select(key, choices, { selected: selected }, class: Views::Base::FIELD) }
  end
end
