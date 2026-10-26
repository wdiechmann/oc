class Views::Monitoring::Scopes < Views::Base
  def initialize(workspaces:, **options)
    super(**options)
    @workspaces = workspaces
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Monitoring" }
    p(class: "mt-3 text-stone-600") { "Choose an administration scope. EP checks your current access on every request." }
    if Monitoring::Reporter.sources.empty?
      p(class: "mt-5 rounded-lg bg-amber-50 p-4 text-sm") { "TOM reporting is not enabled. Ask a platform administrator to enable it; existing monitoring records remain available." }
    end
    ul(class: "mt-8 space-y-4") do
      @workspaces.fetch("tenants", []).each do |tenant|
        li { a(href: tenant_monitoring_path(tenant.fetch("tenant_id")), class: "font-semibold text-emerald-800 underline") { tenant.fetch("name") } }
      end
      @workspaces.fetch("occasions", []).each do |occasion|
        li { a(href: tenant_monitoring_path(occasion.fetch("tenant_id"), occasion_id: occasion.fetch("occasion_id")), class: "font-semibold text-emerald-800 underline") { "#{occasion['name']} · #{occasion['tenant_name']}" } }
      end
    end
    p(class: "mt-8 text-stone-500") { "No monitoring scopes available." } if @workspaces.fetch("tenants", []).empty? && @workspaces.fetch("occasions", []).empty?
  end
end
