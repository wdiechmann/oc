class Views::Books::Show < Views::Base
  def initialize(data:, detail:, key:, **options)
    super(**options)
    @data, @detail, @key = data, detail, key
  end
  def view_template
    div(id: "vera-book-content", class: "max-w-3xl") do
      tid = @data.fetch("tenant_id")
      book = @detail["book"]
      bid = @detail.fetch("book_id", book && book["book_id"])
      header(class: "flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-3xl font-semibold") { book ? book.fetch("name") : "Book setup accepted" }
        render Components::ContextMenu.new(id: "book-header-actions", label: "Book actions") do
          if @detail["status"] == "ready" && book
            a(href: edit_dialog_tenant_book_path(tid, bid), role: "menuitem", data: { turbo_stream: true }, class: "vera-menu-item") { "Edit name and hierarchy" }
          else
            button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Edit name and hierarchy" }
          end
          a(href: tenant_books_path(tid), role: "menuitem", class: "vera-menu-item") { "Back to books" }
          a(href: tenant_book_setup_path(tid, bid), role: "menuitem", class: "vera-menu-item") { "Roles and occasions" }
          a(href: tenant_book_chart_path(tid, bid), role: "menuitem", class: "vera-menu-item") { "Chart of accounts" }
          a(href: tenant_book_periods_path(tid, bid), role: "menuitem", class: "vera-menu-item") { "Accounting periods" }
          a(href: tenant_book_catalogues_path(tid, bid), role: "menuitem", class: "vera-menu-item") { "VAT and categories" }
          a(href: tenant_book_path(tid, bid), role: "menuitem", class: "vera-menu-item") { "Refresh book" }
        end
      end
      if @detail["status"] != "ready"
        p(role: "status", class: "mt-6 rounded-lg border border-amber-200 bg-amber-50 p-4") { "The book view is updating. Refresh shortly; editing is available when the accepted revision has been projected." }
      else
        p(class: "mt-3 text-sm text-stone-500") { "#{book['code']} · Draft · Revision #{book['version']}" }
        dl(class: "mt-6 grid grid-cols-1 gap-4 rounded-xl border border-stone-200 bg-white p-6 sm:grid-cols-2") do
          { "Currency"=>book["base_currency"], "Accounting authority"=>book["accounting_authority"], "Timezone"=>book["timezone"], "Financial year starts"=>Date::MONTHNAMES[book["fiscal_year_start_month"]] }.each do |label, value|
            div { dt(class: "text-xs text-stone-500") { label }; dd(class: "mt-1 font-medium") { value } }
          end
        end
        p(class: "mt-4 text-sm leading-relaxed text-stone-500") { "This is a draft accounting context. Maintain its chart and accounting periods separately; setup access grants no posting/payment authority." }
      end
    end
  end
end
