class Components::MonitoringSettings < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(tenant_id:, occasion_id:, sources:, rules:, assignees:, alerts:, codes:, key:)
    @tenant, @occasion, @sources, @rules, @people, @alerts, @codes, @key = tenant_id, occasion_id, sources, rules, assignees, alerts, codes, key
  end
  def view_template
    a(href: monitoring_list_path(@tenant, occasion_id: @occasion), class: "font-semibold text-emerald-800 underline") { "← Monitoring" }
    h1(class: "mt-5 text-3xl font-semibold") { "Reporting sources and alerts" }
    p(class: "mt-3 text-sm text-stone-600") { "EP checks current administration rights. Reporting bindings do not grant access to business data or expose backend secrets." }
    a(href: monitoring_settings_path(@tenant, occasion_id: @occasion), class: "mt-4 inline-block font-semibold underline", data: { turbo_stream: true }) { "Refresh settings" }
    section(class: "mt-7 rounded-xl border border-stone-200 bg-white p-5") do
      h2(class: "text-xl font-semibold") { "Reporting sources" }
      @sources.fetch("sources").each do |source|
        div(class: "mt-4 break-words border-t border-stone-200 pt-4") do
          p { "#{source['backend_id']} · #{source['status']} · #{source['occasion_id'] || 'Tenant / platform'}" }
          p(class: "mt-1 break-all font-mono text-xs") { source["source_id"] }
          if source["status"] == "active"
            configuration_form("revoke", record: source["source_id"]) { |f| f.submit("Revoke reporting", class: Views::Base::BUTTON) }
          end
        end
      end
      configuration_form("register") do |f|
        f.label(:backend_id, "Approved application", class: "mt-5 block text-sm")
        f.select(:backend_id, @sources.fetch("backends"), {}, class: Views::Base::FIELD)
        f.submit("Register source in this scope", class: Views::Base::BUTTON)
      end
    end
    section(class: "mt-7 rounded-xl border border-stone-200 bg-white p-5") do
      h2(class: "text-xl font-semibold") { "New alert rule" }
      configuration_form("rule") do |f|
        f.label(:source_id, "Reporting source", class: "mt-4 block text-sm")
        f.select(:source_id, @sources.fetch("sources").select { |s| s["status"] == "active" }.map { |s| [ "#{s['backend_id']} · #{s['occasion_id'] || 'this scope'}", s["source_id"] ] }, {}, class: Views::Base::FIELD)
        f.label(:code, "Condition code", class: "mt-4 block text-sm")
        f.select(:code, @codes.map { |code, info| [ "#{code} · #{info['severity']}", code ] }, {}, class: Views::Base::FIELD)
        { threshold: [ "Occurrences in window", 10 ], window_seconds: [ "Window (seconds)", 60 ], cooldown_seconds: [ "Notification cooldown (seconds)", 300 ] }.each do |field, (label, default)|
          f.label(field, label, class: "mt-4 block text-sm")
          f.number_field(field, value: default, min: 1, required: true, class: Views::Base::FIELD)
        end
        f.label(:delivery_backend_id, "Delivery application", class: "mt-4 block text-sm")
        f.select(:delivery_backend_id, @sources.fetch("backends"), {}, class: Views::Base::FIELD)
        fieldset(class: "mt-5") do
          legend(class: "text-sm font-semibold") { "Notify current administrators (up to ten)" }
          @people.each do |person|
            div(class: "mt-2 flex items-center gap-3") do
              f.check_box(:recipient_ids, { multiple: true, id: "recipient-#{person['identity_id']}" }, person.fetch("identity_id"), nil)
              f.label(:recipient_ids, person.fetch("label"), for: "recipient-#{person['identity_id']}")
            end
          end
        end
        p(class: "mt-3 text-xs text-stone-500") { "Expected input rejections usually need aggregation. Test locally before enabling real notifications." }
        f.submit("Create rule", class: Views::Base::BUTTON)
      end
    end
    section(class: "mt-7 rounded-xl border border-stone-200 bg-white p-5") do
      h2(class: "text-xl font-semibold") { "Current rules" }
      @rules.each do |rule|
        div(class: "mt-5 border-t border-stone-200 pt-4") do
          p(class: "font-semibold") { rule["code"] }
          p(class: "mt-2 text-sm") { "#{rule['threshold']} in #{rule['window_seconds']}s · cooldown #{rule['cooldown_seconds']}s · #{rule['enabled'] ? 'Enabled' : 'Disabled'}" }
          p(class: "mt-2 text-sm") { "Suppressed until: #{rule['suppressed_until'] || 'No suppression'}" }
          configuration_form("rule_state", record: rule["rule_id"]) do |f|
            f.hidden_field(:expected_version, value: rule["version"])
            f.hidden_field(:enabled, value: !rule["enabled"])
            f.submit(rule["enabled"] ? "Disable rule" : "Enable rule", class: Views::Base::BUTTON)
          end
          configuration_form("suppression", record: rule["rule_id"]) do |f|
            f.hidden_field(:expected_version, value: rule["version"])
            f.label(:until, "Maintenance suppression ends (UTC, maximum 24 hours)", class: "mt-4 block text-xs")
            f.datetime_local_field(:until, required: true, class: Views::Base::FIELD)
            f.submit("Suppress notifications", class: Views::Base::BUTTON)
          end
        end
      end
    end
    section(class: "mt-7") do
      h2(class: "text-xl font-semibold") { "Recent alert outcomes" }
      p(class: "mt-2 text-xs text-stone-500") { "Unknown sends require reconciliation; they are never automatically resent. Provider acceptance does not prove inbox delivery." }
      @alerts.each do |alert|
        p(class: "mt-3 break-words rounded-lg border border-stone-200 bg-white p-4 text-sm") { "#{alert['code']} · #{alert['state']} · #{alert['updated_at']}" }
      end
    end
  end
  private
  def configuration_form(action, record: nil, &block)
    form_with(url: monitoring_settings_path(@tenant), class: "mt-4") do |f|
      f.hidden_field(:idempotency_key, value: @key)
      f.hidden_field(:configuration_action, value: action)
      f.hidden_field(:record_id, value: record) if record
      f.hidden_field(:occasion_id, value: @occasion) if @occasion
      yield f
    end
  end
end
