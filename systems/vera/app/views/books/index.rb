class Views::Books::Index < Views::Base
  def initialize(data:, **options)
    super(**options)
    @data = data
  end
  def view_template
    div(id: "vera-book-content") do
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("tenant_name", "Tenant") }
      header(class: "mt-3 flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-4xl font-semibold tracking-tight") { "Accounting books" }
        render Components::ContextMenu.new(id: "books-header-actions", label: "Books actions") do
          a(href: new_tenant_book_path(@data.fetch("tenant_id")), role: "menuitem", class: "vera-menu-item") { "Create book" }
          a(href: tenant_books_path(@data.fetch("tenant_id")), role: "menuitem", class: "vera-menu-item") { "Refresh books" }
          a(href: root_path, role: "menuitem", class: "vera-menu-item") { "Your workspaces" }
        end
      end
      p(class: "mt-4 max-w-2xl leading-relaxed text-stone-600") { "Keep occasion books distinct or nest them under a parent context. Consolidation across books is a separate workflow." }
      p(role: "status", class: "mt-6 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm") { "Accepted changes are still being projected. Refresh shortly for the latest view." } if @data["status"] == "pending"
      p(class: "mt-5 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      render Components::BookList.new(tenant_id: @data.fetch("tenant_id"), books: @data.fetch("books"))
    end
  end
end
