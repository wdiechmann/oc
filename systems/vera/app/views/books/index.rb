class Views::Books::Index < Views::Base
  def initialize(data:, **options)
    super(**options)
    @data = data
  end
  def view_template
    div(id: "vera-book-content") do
      a(href: root_path, class: "text-sm font-medium text-teal-900 hover:underline") { "← Your workspaces" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("tenant_name", "Tenant") }
      h1(class: "mt-3 text-4xl font-semibold tracking-tight") { "Accounting books" }
      p(class: "mt-4 max-w-2xl leading-relaxed text-stone-600") { "Keep occasion books distinct or nest them under a parent context. These draft contexts do not yet post transactions or calculate consolidated balances." }
      div(class: "mt-7 flex flex-wrap items-center gap-5") do
        a(href: new_tenant_book_path(@data.fetch("tenant_id")), class: BUTTON) { "Create book" }
        a(href: tenant_books_path(@data.fetch("tenant_id")), class: "mt-5 text-sm font-medium text-teal-900 hover:underline") { "Refresh books" }
      end
      p(role: "status", class: "mt-6 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm") { "Accepted changes are still being projected. Refresh shortly for the latest view." } if @data["status"] == "pending"
      p(class: "mt-5 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      render Components::BookList.new(tenant_id: @data.fetch("tenant_id"), books: @data.fetch("books"))
    end
  end
end
