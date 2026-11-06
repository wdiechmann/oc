class Views::Monitoring::Scopes < Views::Base
  def initialize(workspaces:, platform: false, **options)
    super(**options)
    @workspaces, @platform = workspaces, platform
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Monitoring" }
    p(class: "mt-3 text-stone-600") { "Choose an administration scope. EP checks your current access on every request." }
    a(href: platform_monitoring_path, class: "mt-5 block font-semibold text-emerald-800 underline") { "Platform monitoring (restricted)" } if @platform
    ul(class: "mt-8 space-y-4") do
      @workspaces.fetch("tenants", []).each do |tenant|
        li { a(href: tenant_monitoring_path(tenant.fetch("tenant_id")), class: "font-semibold text-emerald-800 underline") { tenant.fetch("name") } }
      end
      @workspaces.fetch("occasions", []).each do |occasion|
        li { a(href: tenant_monitoring_path(occasion.fetch("tenant_id"), occasion_id: occasion.fetch("occasion_id")), class: "font-semibold text-emerald-800 underline") { "#{occasion['name']} · #{occasion['tenant_name']}" } }
      end
    end
    details(id: "monitoring-reporting-status", class: "mt-8 border-t border-stone-200 pt-4 text-sm text-stone-600") do
      summary(class: "cursor-pointer font-medium text-emerald-800") { "Reporting setup" }
      p(class: "mt-3") do
        Monitoring::Reporter.sources.empty? ? "No reporting sources are currently visible to this TOM process. Setup may be missing, or discovery may be unavailable. Existing records remain readable." : "Reporting sources are available to this TOM process. This does not confirm delivery of every observation."
      end
      p(class: "mt-2") { Monitoring::Dispatcher.heartbeat_fresh? ? "Alert worker: a successful check was recorded within the last 30 seconds on this instance." : "Alert worker: no successful check was recorded within the last 30 seconds on this instance." }
      p(class: "mt-2") { "The alert worker sends alerts; reporting sources configure which observations TOM can record. Open a scope’s settings to review its sources and alert rules." }
      @workspaces.fetch("tenants", []).each do |tenant|
        a(href: monitoring_settings_path(tenant.fetch("tenant_id")), class: "mt-3 block text-emerald-800 underline") { "#{tenant['name']} · Reporting settings" }
      end
      @workspaces.fetch("occasions", []).each do |occasion|
        a(href: monitoring_settings_path(occasion.fetch("tenant_id"), occasion_id: occasion.fetch("occasion_id")), class: "mt-3 block text-emerald-800 underline") { "#{occasion['name']} · Reporting settings" }
      end
    end
    p(class: "mt-8 text-stone-500") { "No monitoring scopes available." } if @workspaces.fetch("tenants", []).empty? && @workspaces.fetch("occasions", []).empty?
  end
end
