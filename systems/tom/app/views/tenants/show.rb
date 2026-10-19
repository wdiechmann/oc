class Views::Tenants::Show < Views::Base
  def initialize(tenant:, **options)
    super(**options)
    @tenant = tenant
  end

  def view_template
    a(href: root_path, class: "text-sm font-medium text-emerald-800 hover:underline") { "← Your tenants" }
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
    p(class: "mt-6 text-sm text-stone-500") { "Occasion creation and administrator delegation are coming in the next implementation step." }
  end
end
