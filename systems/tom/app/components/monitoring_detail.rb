class Components::MonitoringDetail < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(tenant_id:, id:, occasion_id:, data:, timeline:, key:)
    @tenant, @id, @occasion, @data, @timeline, @key = tenant_id, id, occasion_id, data, timeline, key
  end

  def view_template
    a(href: tenant_monitoring_path(@tenant, occasion_id: @occasion), class: "font-semibold text-emerald-800 underline") { "← Monitoring list" }
    h1(class: "mt-6 text-3xl font-semibold") { "Issue details" }
    p(class: "mt-3 break-all font-mono text-xs") { @id }
    a(href: tenant_monitoring_issue_path(@tenant, @id, occasion_id: @occasion), class: "mt-5 inline-block font-semibold text-emerald-800 underline", data: { turbo_stream: true }) { "Refresh issue" }
    p(role: "status", class: "mt-5 rounded-lg bg-amber-50 p-4") { "The view is updating. Accepted version: #{@data['expected_version']}." } if @data["status"] == "pending"
    row = @data["issue"]
    return unless row
    data = row.fetch("data")
    section(class: "mt-6 rounded-xl border border-stone-200 bg-white p-6") do
      h2(class: "text-xl font-semibold") { data["safe_message"] }
      dl(class: "mt-5 grid gap-4 sm:grid-cols-2") do
        { "Severity" => data["severity"], "State" => data["state"], "Application" => data["application"], "Code" => data["code"], "Occurrences" => data["count"], "Outcome" => data["outcome"], "First seen" => data["first_seen"], "Last seen" => data["last_seen"], "Owner" => data["owner_identity_id"] || "Unassigned", "View version" => row["source_version"], "Correlation reference" => data["correlation_id"] }.each do |label, value|
          div(class: "min-w-0") { dt(class: "text-xs text-stone-500") { label }; dd(class: "mt-1 break-words text-sm") { value.to_s } }
        end
      end
    end
    section(class: "mt-6 grid gap-4 sm:grid-cols-2") do
      %w[acknowledge assign resolve reopen].each do |action|
        form_with(url: tenant_monitoring_issue_action_path(@tenant, @id), class: "rounded-xl border border-stone-200 bg-white p-5") do |f|
          f.hidden_field(:idempotency_key, value: @key)
          f.hidden_field(:action_name, value: action)
          f.hidden_field(:expected_version, value: @data["expected_version"])
          h2(class: "font-semibold") { action.capitalize }
          if action == "assign"
            f.label(:owner_identity_id, "Current administrator identity ID", class: "mt-3 block text-xs")
            f.text_field(:owner_identity_id, required: true, class: Views::Base::FIELD)
          elsif action == "resolve"
            f.label(:reason, "Resolution reason", class: "mt-3 block text-xs")
            f.select(:reason, [ [ "Corrected", "corrected" ], [ "Duplicate", "duplicate" ], [ "Accepted risk", "accepted_risk" ] ], {}, class: Views::Base::FIELD)
          end
          f.submit(action.capitalize, class: Views::Base::BUTTON)
        end
      end
    end
    p(class: "mt-4 text-xs text-stone-500") { "Acknowledgment or resolution does not prove recovery and never retries a business action or sends a message." }
    section(class: "mt-9") do
      h2(class: "text-xl font-semibold") { "Timeline · newest first" }
      ol(class: "mt-4 space-y-3") do
        @timeline.fetch("items", []).each do |entry|
          details = entry.fetch("data", {})
          li(class: "break-words rounded-lg border border-stone-200 bg-white p-4 text-sm") do
            p(class: "font-semibold") { details["event_type"] || details["code"] }
            p(class: "mt-1 text-stone-500") { "Version #{entry['source_version']} · #{details['received_at'] || entry['updated_at']}" }
            p { details["safe_message"] }
          end
        end
      end
      if @timeline["next_cursor"]
        a(href: tenant_monitoring_issue_path(@tenant, @id, occasion_id: @occasion, timeline_cursor: @timeline["next_cursor"]), class: "mt-5 inline-block font-semibold text-emerald-800 underline", data: { turbo_stream: true }) { "Older timeline entries →" }
      end
    end
  end
end
