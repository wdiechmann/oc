class Views::Home::Workspace < Views::Base
  def initialize(workspaces:, **options)
    super(**options)
    @workspaces = workspaces
  end
  def view_template
    p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { "Your financial workspace" }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Your tenants and occasions" }
    p(class: "mt-4 max-w-2xl leading-relaxed text-stone-600") { "EP supplies your current access. Invitations and identity administration remain in TOM; tenant administrators can set up their books in VERA." }
    div(class: "mt-8 grid gap-6 md:grid-cols-2", aria_label: "Authorized workspaces") do
      tenants_column
      occasions_column
    end
    a(href: Notifications::Delivery.tom_origin, class: "mt-8 inline-block font-medium text-teal-900 hover:underline", data: { turbo: false }) { "Manage identity and invitations in TOM" }
  end
  private
  def tenants_column
    tenants = @workspaces.fetch("tenants").index_by { |tenant| tenant["tenant_id"] }
    books = @workspaces.fetch("finance_books", []).group_by { |book| book["tenant_id"] }
    books.each { |tid, rows| tenants[tid] ||= { "tenant_id"=>tid, "name"=>rows.first["tenant_name"], "role"=>"finance_configuration_steward" } }
    section(aria_labelledby: "workspace-tenants-title", class: "min-w-0") do
      h2(id: "workspace-tenants-title", class: "text-2xl font-semibold") { "Tenant" }
      div(class: "mt-4 space-y-4") do
        p(class: "text-sm text-stone-500") { "No tenants are currently available." } if tenants.empty?
        tenants.each_value do |tenant|
          admin = @workspaces.fetch("tenants").any? { |row| row["tenant_id"] == tenant["tenant_id"] }
          article(class: "rounded-2xl border border-stone-200 bg-white p-6") do
            h3(class: "text-xl font-semibold") { tenant.fetch("name") }
            p(class: "mt-2 text-sm text-stone-500") { admin ? "Tenant administrator" : "Finance configuration steward" }
            a(href: tenant_books_path(tenant["tenant_id"]), class: "mt-5 inline-block font-medium text-teal-900 hover:underline") { "Open books" } if admin
            Array(books[tenant["tenant_id"]]).each do |book|
              p(class: "mt-3") do
                a(href: tenant_book_path(book.fetch("tenant_id"), book.fetch("book_id")), class: "font-medium text-teal-900 hover:underline") { book.fetch("name") }
              end
            end
          end
        end
      end
    end
  end
  def occasions_column
    section(aria_labelledby: "workspace-occasions-title", class: "min-w-0") do
      h2(id: "workspace-occasions-title", class: "text-2xl font-semibold") { "Occasion" }
      div(class: "mt-4 space-y-4") do
        p(class: "text-sm text-stone-500") { "No occasions are currently available." } if @workspaces.fetch("occasions").empty?
        @workspaces.fetch("occasions").each do |occasion|
          article(class: "rounded-2xl border border-stone-200 bg-white p-6") do
            h3(class: "text-xl font-semibold") { occasion.fetch("name") }
            p(class: "mt-2 text-sm text-stone-500") { occasion.fetch("tenant_name") }
            if occasion["book_id"]
              a(href: tenant_book_path(occasion.fetch("tenant_id"), occasion.fetch("book_id")), class: "mt-5 inline-block font-medium text-teal-900 hover:underline") { "Open book#{occasion['book_name'].present? ? ' · '+occasion['book_name'] : ''}" }
            else
              p(class: "mt-5 text-xs text-stone-500") { "No accessible book is linked to this occasion." }
            end
          end
        end
      end
    end
  end
end
