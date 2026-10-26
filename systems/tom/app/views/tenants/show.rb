class Views::Tenants::Show < Views::Base
  def initialize(tenant:, occasions:, **options)
    super(**options)
    @tenant = tenant
    @occasions = occasions
  end

  def view_template
    a(href: root_path, class: "text-sm font-medium text-emerald-800 hover:underline") { "← Your tenants" }
    a(href: tenant_monitoring_path(@tenant["tenant_id"]), class: "mt-5 block font-semibold text-emerald-800 underline") { "Monitoring →" }
    section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8 md:p-12") do
      p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "Tenant overview" }
      h1(class: "mt-4 text-4xl font-semibold tracking-tight") { @tenant["status"] == "pending" ? "Preparing your tenant" : @tenant["name"] }
      p(class: "mt-4 break-all font-mono text-xs text-stone-500") { @tenant["tenant_id"] }
      if @tenant["status"] == "pending"
        p(class: "mt-8 text-stone-600") { "Your tenant has been recorded. Its overview is being prepared." }
      else
        dl(class: "mt-10 grid gap-8 border-t border-stone-200 pt-8 sm:grid-cols-2") do
          div do
            dt(class: "text-sm text-stone-500") { "Status" }
            dd(class: "mt-2 font-semibold text-emerald-800") { "Ready" }
          end
          div do
            dt(class: "text-sm text-stone-500") { "Projection version" }
            dd(class: "mt-2 font-semibold", data_source_version: true) { @tenant["source_version"].to_s }
          end
        end
      end
      a(href: tenant_path(@tenant["tenant_id"]), class: "mt-8 inline-block text-sm font-semibold text-emerald-800 hover:underline") { "Refresh status" }
    end
    a(href: tenant_admin_invitations_path(@tenant["tenant_id"]), class: "mt-6 inline-block text-sm font-semibold text-emerald-800 hover:underline") { "Invite tenant admins →" }
    section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8") do
      div(class: "flex flex-wrap items-center justify-between gap-4") do
        h2(class: "text-2xl font-semibold") { "Occasions" }
        a(href: new_tenant_occasion_path(@tenant["tenant_id"]), class: "rounded-lg bg-emerald-900 px-5 py-3 text-sm font-semibold text-white hover:bg-emerald-800") { "Create occasion" }
      end
      p(class: "mt-5 text-sm text-stone-500") { "An occasion overview is being prepared. Refresh to see the latest changes." } if @occasions["status"] == "pending"
      if @occasions.fetch("occasions").empty?
        p(class: "mt-7 text-stone-500") { "No occasions to show yet. Create the first one when you’re ready." }
      else
        ul(class: "mt-6 divide-y divide-stone-200") do
          @occasions.fetch("occasions").each do |occasion|
            li(class: "flex flex-wrap items-center justify-between gap-3 py-5") do
              a(href: tenant_occasion_path(@tenant["tenant_id"], occasion.fetch("occasion_id")), class: "font-semibold text-emerald-800 hover:underline") { occasion.fetch("name") }
              span(class: "rounded-full bg-stone-100 px-3 py-1 text-xs text-stone-600") { occasion.fetch("lifecycle").capitalize }
            end
          end
        end
      end
    end
  end
end
