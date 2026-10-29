class Components::BookForm < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(tenant_id:, books:, key:, book: nil, **options)
    @tenant, @books, @key, @book = tenant_id, books, key, book
  end
  def view_template
    form_with(url: @book ? tenant_book_path(@tenant, @book.fetch("book_id")) : tenant_books_path(@tenant), method: @book ? :patch : :post, class: "mt-7 rounded-2xl border border-stone-200 bg-white p-6 sm:p-8") do |f|
      f.hidden_field(:idempotency_key, value: @key)
      f.hidden_field(:expected_version, value: @book.fetch("version")) if @book
      field(f, :name, "Book name") { f.text_field(:name, value: @book && @book["name"], required: true, maxlength: 120, class: FIELD) }
      unless @book
        field(f, :code, "Book code") { f.text_field(:code, required: true, minlength: 2, pattern: "[A-Za-z0-9](?:[A-Za-z0-9_]|-){1,39}", maxlength: 40, placeholder: "SL2030", class: FIELD) }
        p(class: "mt-2 text-xs text-stone-500") { "2–40 letters, digits, underscores or hyphens; unique within this tenant. Code and financial configuration are fixed after creation in this first slice." }
        field(f, :base_currency, "Book currency") { f.select(:base_currency, %w[DKK EUR SEK NOK GBP USD], { selected: "DKK" }, class: FIELD) }
        field(f, :accounting_authority, "Authority for posted accounting") { f.select(:accounting_authority, [ [ "EP", "ep" ], [ "External accounting system", "external" ] ], {}, class: FIELD) }
        field(f, :timezone, "Accounting timezone") { f.select(:timezone, [ "Europe/Copenhagen", "Etc/UTC" ], {}, class: FIELD) }
        field(f, :fiscal_year_start_month, "Financial year starts in month") { f.select(:fiscal_year_start_month, (1..12).map { |m| [ Date::MONTHNAMES[m], m ] }, {}, class: FIELD) }
      end
      options = @books.reject { |b| @book && b["book_id"] == @book["book_id"] }.map { |b| [ "#{b['code']} · #{b['name']}", b.fetch("book_id") ] }
      field(f, :parent_book_id, "Parent book") { f.select(:parent_book_id, options, { include_blank: "No parent — root book", selected: @book && @book["parent_book_id"] }, class: FIELD) }
      p(class: "mt-3 text-xs leading-relaxed text-stone-500") { "A parent nests context using the same records and protocol. Consolidation and financial permissions are separate workflows; EP rejects cycles and foreign-tenant parents." }
      f.submit(@book ? "Save book setup" : "Create draft book", class: BUTTON)
    end
  end
  private
  def field(f, name, label)
    f.label(name, label, class: "mt-5 block text-sm font-medium first:mt-0")
    yield
  end
end
