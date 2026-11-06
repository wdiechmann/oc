class Views::VatRules::Show < Views::Base
  def initialize(data:, token:, selected_entry: nil, as_of: nil, draft: nil, message: nil, check_url: nil, retry_url: nil, **options)
    @data, @as_of, @message = data, as_of, (selected_entry ? nil : message)
    @as_of ||= Time.current.in_time_zone("Europe/Copenhagen").to_date
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    dialog = if selected_entry
      Views::VatRules::Detail.new(data: data, token: token, selected_entry: selected_entry, as_of: @as_of, draft: draft, message: message, check_url: check_url, retry_url: retry_url)
    end
    super(dialog: dialog, **options)
  end
  def view_template
    div(id: "vera-book-content") do
      header(class: "flex flex-wrap items-end justify-between gap-4") do
        div do
          p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
          h1(class: "mt-2 text-3xl font-semibold") { "VAT codes" }
          p(class: "mt-2 text-sm text-stone-600") { "Open a code to see its settings and references." }
        end
        a(href: tenant_book_catalogues_path(@tid, @bid), class: "text-sm text-teal-900 underline") { "Code names and categories" }
      end
      p(role: "alert", class: "mt-4 rounded bg-amber-50 p-3") { @message } if @message
      p(role: "status", class: "mt-4 text-amber-900") { "The view is updating. Refresh before saving changes." } unless @data["status"] == "ready"
      form_with(url: tenant_book_vat_rules_path(@tid, @bid), method: :get, class: "mt-5 flex flex-wrap items-end gap-3", id: "vat-settings-date") do |f|
        div { f.label(:as_of, "Settings valid on"); f.date_field(:as_of, value: @as_of.iso8601, required: true, class: FIELD) }
        f.submit("Show", class: BUTTON)
      end
      div(class: "mt-6 overflow-x-auto rounded-lg border border-stone-200 bg-white") do
        table(class: "w-full text-left text-sm") do
          thead(class: "border-b bg-stone-100 text-stone-600") do
            tr { %w[Code Name VAT Deductible Status].each { |label| th(scope: "col", class: "px-4 py-3 font-medium") { label } } }
          end
          tbody do
            @data.fetch("vat_entries").each { |entry| render Components::VatCodeRow.new(data: @data, entry: entry, as_of: @as_of) }
            tr { td(colspan: 5, class: "px-4 py-6 text-stone-500") { "No VAT codes yet. Add one under Code names and categories." } } if @data.fetch("vat_entries").empty?
          end
        end
      end
    end
  end
end
