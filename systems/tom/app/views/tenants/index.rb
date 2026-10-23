class Views::Tenants::Index < Views::Base
  def initialize(key:, last_tenant_id: nil, workspaces: {}, **options)
    super(**options)
    @key, @last_tenant_id, @workspaces = key, last_tenant_id, workspaces
  end

  def view_template
    p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "Your foundation" }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Bring your organization together." }
    p(class: "mt-4 max-w-2xl text-stone-600 leading-relaxed") { "A tenant is your organization’s shared workspace. Each camp or other occasion will live within it." }
    unless @workspaces.fetch("tenants", []).empty? && @workspaces.fetch("occasions", []).empty?
      section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8") do
        h2(class: "text-2xl font-semibold") { "Your administration" }
        ul(class: "mt-5 space-y-4") do
          @workspaces.fetch("tenants", []).each do |tenant|
            li { a(href: tenant_path(tenant.fetch("tenant_id")), class: "font-semibold text-emerald-800 hover:underline") { tenant.fetch("name") } }
          end
          @workspaces.fetch("occasions", []).each do |occasion|
            li do
              a(href: tenant_occasion_path(occasion.fetch("tenant_id"), occasion.fetch("occasion_id")), class: "font-semibold text-emerald-800 hover:underline") { occasion.fetch("name") }
              span(class: "ml-3 text-sm text-stone-500") { occasion.fetch("tenant_name") }
            end
          end
        end
      end
    end
    div(class: "mt-10 grid gap-6 md:grid-cols-2") do
      section(class: "rounded-2xl border border-stone-200 bg-white p-8") do
        h2(class: "text-xl font-semibold") { "Create a tenant" }
        p(class: "mt-2 text-sm text-stone-500") { "You’ll become its first tenant administrator." }
        form_with(url: tenants_path) do |f|
          div(class: "mt-6") do
            f.hidden_field(:idempotency_key, value: @key)
            f.label(:name, "Organization name", class: "text-sm font-medium")
            f.text_field(:name, required: true, maxlength: 120, placeholder: "Spejdernes Lejr", class: FIELD)
            f.submit("Create tenant", class: BUTTON)
          end
        end
      end
      section(class: "rounded-2xl border border-stone-200 bg-white p-8") do
        h2(class: "text-xl font-semibold") { "Open an existing tenant" }
        p(class: "mt-2 text-sm text-stone-500") { "Enter its ID. Your current access is checked when you open it." }
        form_with(url: open_tenant_path) do |f|
          div(class: "mt-6") do
            f.label(:tenant_id, "Tenant ID", class: "text-sm font-medium")
            f.text_field(:tenant_id, required: true, value: @last_tenant_id, class: FIELD)
            f.submit("Open tenant", class: BUTTON)
          end
        end
      end
    end
  end
end
