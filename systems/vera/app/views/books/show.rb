class Views::Books::Show < Views::Base
  def initialize(data:, detail:, key:, **options)
    super(**options)
    @data, @detail, @key = data, detail, key
  end
  def view_template
    div(id: "vera-book-content", class: "max-w-3xl") do
      tid = @data.fetch("tenant_id")
      a(href: tenant_books_path(tid), class: "text-sm font-medium text-teal-900 hover:underline") { "← Books" }
      a(href: tenant_book_setup_path(tid, @detail.fetch("book_id", @detail.dig("book", "book_id"))), class: "ml-5 text-sm font-medium text-teal-900 hover:underline") { "Roles and occasions" }
      a(href: tenant_book_chart_path(tid, @detail.fetch("book_id", @detail.dig("book", "book_id"))), class: "ml-5 text-sm font-medium text-teal-900 hover:underline") { "Chart of accounts" }
      a(href: tenant_book_periods_path(tid, @detail.fetch("book_id", @detail.dig("book", "book_id"))), class: "ml-5 text-sm font-medium text-teal-900 hover:underline") { "Accounting periods" }
      book = @detail["book"]
      h1(class: "mt-6 text-3xl font-semibold") { book ? book.fetch("name") : "Book setup accepted" }
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
        h2(class: "mt-8 text-xl font-semibold") { "Name and hierarchy" }
        render Components::BookForm.new(tenant_id: tid, books: @data.fetch("books"), book: book, key: @key)
      end
      a(href: tenant_book_path(tid, @detail.fetch("book_id", book && book["book_id"])), class: "mt-7 inline-block text-sm font-medium text-teal-900 hover:underline") { "Refresh book" }
    end
  end
end
