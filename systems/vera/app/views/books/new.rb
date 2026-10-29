class Views::Books::New < Views::Base
  def initialize(data:, key:, **options)
    super(**options)
    @data, @key = data, key
  end
  def view_template
    div(id: "vera-book-content", class: "max-w-2xl") do
      a(href: tenant_books_path(@data.fetch("tenant_id")), class: "text-sm font-medium text-teal-900 hover:underline") { "← Books" }
      h1(class: "mt-6 text-3xl font-semibold") { "Create a book" }
      p(class: "mt-3 text-sm text-stone-600") { @data.fetch("tenant_name", "Tenant book setup") }
      render Components::BookForm.new(tenant_id: @data.fetch("tenant_id"), books: @data.fetch("books"), key: @key)
    end
  end
end
