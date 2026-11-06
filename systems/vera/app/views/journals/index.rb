class Views::Journals::Index < Views::Base
  def initialize(data:, message: nil, **options)
    super(**options)
    @data, @message = data, message
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    div(id: "vera-book-content") do
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      header(class: "mt-2 flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-3xl font-semibold") { "Journals" }
        render Components::ContextMenu.new(id: "journals-index-actions", label: "Journals actions") do
          a(href: tenant_book_chart_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "Chart of accounts" }
          a(href: tenant_book_journals_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "Refresh journals" }
          if @data["status"] == "ready" && @data.dig("permissions", "prepare")
            a(href: new_tenant_book_journals_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "New journal" }
          else
            button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "New journal" }
          end
        end
      end
      render Components::Toast.new(message: @message, kind: "alert") if @message
      p(role: "status", class: "mt-4 text-sm text-amber-900") { "The journal list is updating. Refresh to see the latest changes." } unless @data["status"] == "ready"
      div(class: "mt-6 overflow-x-auto rounded-lg border border-stone-200 bg-white") do
        table(class: "w-full text-left text-sm") do
          thead(class: "border-b bg-stone-100") { tr { [ "Journal", "Posting date", "Reference", "Status" ].each { |label| th(scope: "col", class: "px-4 py-3 font-medium") { label } } } }
          tbody do
            @data.fetch("drafts").each do |draft|
              tr(class: "border-b last:border-0 hover:bg-teal-50") do
                td(class: "px-4 py-3") { a(href: tenant_book_journals_path(@tid, @bid, draft_id: draft["id"]), class: "font-medium text-teal-900 underline") { draft.dig("data", "name") } }
                td(class: "px-4 py-3 whitespace-nowrap") { draft.dig("data", "posting_date") }
                td(class: "px-4 py-3") { draft.dig("data", "reference") }
                td(class: "px-4 py-3") { "Work in progress" }
              end
            end
            tr { td(colspan: 4, class: "px-4 py-6 text-stone-500") { "No journals yet." } } if @data.fetch("drafts").empty?
          end
        end
      end
    end
  end
end
