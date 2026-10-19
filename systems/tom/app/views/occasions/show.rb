class Views::Occasions::Show < Views::Base
  def initialize(occasion:, tenant_id:, occasion_id:, **options)
    super(**options)
    @occasion, @tenant_id, @occasion_id = occasion, tenant_id, occasion_id
  end

  def view_template
    a(href: tenant_path(@tenant_id), class: "text-sm font-medium text-emerald-800 hover:underline") { "← Tenant overview" }
    section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8 md:p-12") do
      p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "Occasion overview" }
      h1(class: "mt-4 text-4xl font-semibold tracking-tight") { @occasion["status"] == "pending" ? "Preparing your occasion" : @occasion["name"] }
      if @occasion["status"] == "pending"
        p(class: "mt-5 text-stone-600") { "Your occasion has been recorded. Its overview is being prepared." }
      else
        dl(class: "mt-10 grid gap-8 border-t border-stone-200 pt-8 sm:grid-cols-2") do
          { "Short name" => @occasion["slug"], "Lifecycle" => @occasion["lifecycle"].to_s.capitalize, "Recruitment" => @occasion["recruitment_state"].to_s.capitalize, "Expiry review (UTC)" => @occasion["expires_at"], "Projection version" => @occasion["source_version"].to_s }.each do |label, value|
            div do
              dt(class: "text-sm text-stone-500") { label }
              dd(class: "mt-2 font-semibold") { value }
            end
          end
        end
      end
      a(href: tenant_occasion_path(@tenant_id, @occasion_id), class: "mt-8 inline-block text-sm font-semibold text-emerald-800 hover:underline") { "Refresh status" }
    end
    p(class: "mt-6 text-sm text-stone-500") { "Opening recruitment and assigning other administrators are separate next steps." }
  end
end
