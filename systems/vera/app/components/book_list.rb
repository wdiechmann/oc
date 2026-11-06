class Components::BookList < Components::Base
  def initialize(tenant_id:, books:)
    @tenant, @books = tenant_id, books
  end
  def view_template
    section(class: "mt-7 space-y-4", aria_label: "Book hierarchy") do
      p(class: "rounded-xl border border-stone-200 bg-white p-6") { "No projected books yet. Create your first book, or refresh if a request was just accepted." } if @books.empty?
      by_id = @books.index_by { |b| b.fetch("book_id") }
      children = @books.group_by { |b| b["parent_book_id"] }
      roots = @books.select { |b| !by_id.key?(b["parent_book_id"]) }
      stack = roots.reverse.map { |b| [ b, 0 ] }
      seen = {}
      until stack.empty?
        book, depth = stack.pop
        next if seen[book["book_id"]]
        seen[book["book_id"]] = true
        article(class: "rounded-xl border border-stone-200 bg-white p-5") do
          p(class: "text-xs text-stone-500") { book["parent_book_id"] ? "Level #{depth} · Child of #{by_id.dig(book['parent_book_id'], 'name') || 'parent view unavailable'}" : "Root book" }
          header(class: "mt-2 flex items-center justify-between gap-4") do
            a(href: tenant_book_path(@tenant, book.fetch("book_id")), class: "min-w-0 text-xl font-semibold text-teal-950 hover:underline") { "#{'↳ ' * [ depth, 4 ].min}#{book.fetch('name')}" }
            render Components::ContextMenu.new(id: "book-actions-#{book.fetch('book_id')}", label: "Actions for #{book.fetch('name')}") do
              a(href: tenant_book_setup_path(@tenant, book.fetch("book_id")), role: "menuitem", class: "vera-menu-item") { "Setup" }
              a(href: tenant_book_chart_path(@tenant, book.fetch("book_id")), role: "menuitem", class: "vera-menu-item") { "Chart of accounts" }
              a(href: tenant_book_journals_path(@tenant, book.fetch("book_id")), role: "menuitem", class: "vera-menu-item") { "Journals" }
            end
          end
          p(class: "mt-2 text-sm text-stone-600") { "#{book.fetch('code')} · #{book.fetch('base_currency')} · #{book['accounting_authority'] == 'ep' ? 'EP ledger' : 'External ledger'} · Draft" }
        end
        stack.concat(Array(children[book["book_id"]]).reverse.map { |child| [ child, depth+1 ] })
      end
    end
  end
end
