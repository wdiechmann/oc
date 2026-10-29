class Views::Home::Workspace < Views::Base
  def initialize(workspaces:, **options)
    super(**options)
    @workspaces = workspaces
  end
  def view_template
    p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { "Your financial workspace" }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Your tenants and occasions" }
    p(class: "mt-4 max-w-2xl leading-relaxed text-stone-600") { "EP supplies your current access. Invitations and identity administration remain in TOM; tenant administrators can now set up their books in VERA." }
    section(class: "mt-8 grid gap-4 md:grid-cols-2", aria_label: "Authorized workspaces") do
      @workspaces.fetch("tenants").each { |tenant| workspace(tenant.fetch("name"), "Tenant administrator", tenant["tenant_id"]) }
      @workspaces.fetch("occasions").each { |occasion| workspace(occasion.fetch("name"), "#{occasion.fetch('tenant_name')} · Occasion administrator") }
      if @workspaces.fetch("tenants").empty? && @workspaces.fetch("occasions").empty?
        p(class: "rounded-xl border border-stone-200 bg-white p-6") { "No authorized workspaces are currently available. Review your invitations or access in TOM." }
      end
    end
    a(href: Notifications::Delivery.tom_origin, class: "mt-8 inline-block font-medium text-teal-900 hover:underline", data: { turbo: false }) { "Manage identity and invitations in TOM" }
  end
  private
  def workspace(name, role, tenant_id = nil)
    article(class: "rounded-2xl border border-stone-200 bg-white p-6") do
      h2(class: "text-xl font-semibold") { name }
      p(class: "mt-2 text-sm text-stone-500") { role }
      a(href: tenant_books_path(tenant_id), class: "mt-5 inline-block font-medium text-teal-900 hover:underline") { "Open books" } if tenant_id
      p(class: "mt-5 text-xs text-stone-500") { "Book setup requires tenant administration." } unless tenant_id
    end
  end
end
