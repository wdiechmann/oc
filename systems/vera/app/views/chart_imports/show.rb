class Views::ChartImports::Show < Views::Base
  def initialize(data:, token: nil, message: nil, **options)
    super(**options)
    @data, @token, @message = data, token, message
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    a(href: tenant_book_chart_path(@tid, @bid), class: "text-teal-900 underline") { "← Chart of accounts" }
    h1(class: "mt-6 text-3xl font-semibold") { "Import chart CSV" }
    p(class: "mt-4 text-stone-600") { "Upload → choose replacement or merge → map columns → review → accept. Replacement retires omitted accounts; merge keeps them. History is preserved and all changes are accepted together." }
    p(role: "alert", class: "mt-4 bg-amber-50 p-4") { @message } if @message
    p(class: "mt-3 text-sm text-stone-600") { "VAT values and account categories are separate catalogues: VAT examples include Dansk salgsmoms and UEUV - Varesalg EU; category examples include Aktiv, Passiv and Indtægt. Descriptive text is preserved." }
    p(class: "mt-3 text-sm text-stone-600") { "Types: header, posting, calculation. The demo uses header. Blank types are guessed: numbered rows as posting, formula rows or unnumbered rows after postings as calculation, otherwise header. Check every guess; calculations require a valid formula." }
    if @data["import_id"]
      review
    elsif @data.dig("permissions", "configure") && @data["catalogues_initialized"] && @data["status"] == "ready"
      p(class: "mt-4 text-sm") { "Comma-, semicolon- or tab-separated UTF-8 CSV · 2 MiB · 500 rows · 32 columns. Keep account numbers and IDs as Text in spreadsheet software to preserve leading zeros. Reviews expire after one hour. If active is mapped, use true or false." }
      a(href: template_tenant_book_chart_import_path(@tid, @bid), data: { turbo: false }, class: "mt-4 inline-block underline") { "Download demo template" }
      form_with(url: upload_tenant_book_chart_import_path(@tid, @bid), multipart: true, data: { turbo: false }, class: "mt-6") do |f|
        f.label(:csv, "CSV file")
        f.file_field(:csv, accept: ".csv,text/csv", required: true, class: FIELD)
        import_mode
        create_codes_checkbox
        f.submit("Upload for mapping", class: BUTTON)
      end
    else
      p(class: "mt-5 bg-amber-50 p-4") { "A current steward grant, initialized catalogues and a ready chart are required to import." }
    end
  end
  def review
    p(class: "mt-4 text-sm") { "#{@data['row_count']} records · Expires #{@data['expires_at']}" }
    p(class: "mt-3 text-sm") { "Name and position are required. Type may be unmapped or blank to guess it. Unmapped optional fields preserve existing values; mapped blank cells clear them. Match by account ID, or posting number when ID is blank. Blank IDs on headers/calculations create new rows." }
    details(class: "mt-5 rounded-lg border p-4", open: !@data["plan"]) do
      summary(class: "cursor-pointer font-semibold") { "Column mapping and sample" }
      form_with(url: preview_tenant_book_chart_import_path(@tid, @bid), data: { turbo: false }) do |f|
        f.hidden_field(:import_id, value: @data.fetch("import_id"))
        div(class: "mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3") do
          @data.fetch("columns").each do |column|
            div do
              label(for: "map-#{column}", class: "text-sm font-medium") { column == "type" ? "type (optional; guessed when blank)" : column }
              select(name: "mapping[#{column}]", id: "map-#{column}", class: FIELD) do
                option(value: "") { "Unmapped" }
                @data.fetch("headers").each { |header| option(value: header, selected: @data.dig("mapping", column) == header) { header } }
              end
            end
          end
        end
        import_mode
        create_codes_checkbox
        f.submit("Review mapped changes", class: BUTTON)
      end
      div(class: "mt-5 overflow-x-auto") do
        table(class: "w-full text-left text-sm") do
          thead { tr { @data.fetch("headers").each { |header| th(class: "border p-2") { header } } } }
          tbody { @data.fetch("sample").each { |row| tr { row.each { |cell| td(class: "whitespace-pre-wrap border p-2") { cell } } } } }
        end
      end
    end
    plan = @data["plan"]
    return unless plan
    h2(class: "mt-7 text-xl font-semibold") { "Review at revision #{@data['expected_version']}" }
    p(class: "mt-3 font-semibold") { plan["mode"] == "replace" ? "Replace chart: #{plan.fetch('retained_count', 0)} existing accounts retained; #{Array(plan['retirements']).length} accounts will be retired." : "Merge into existing chart: omitted accounts remain unchanged." }
    p(class: "mt-3") { plan.fetch("counts").map { |key, value| "#{key}: #{value}" }.join(" · ") }
    plan.fetch("errors", []).each { |error| p(class: "mt-3 text-red-800", role: "alert") { error } }
    Array(plan["catalogue_creates"]).each do |entry|
      p(class: "mt-3 rounded-lg border p-3 text-sm") { "Create #{entry['kind'] == "vat" ? "VAT" : "account category"} code: #{entry['code']} · Name: #{entry['name']}" }
    end
    div(class: "mt-4 space-y-3") do
      (plan.fetch("rows") + Array(plan["retirements"])).each do |row|
        details(class: "rounded-lg border p-4", open: row["operation"] == "error") do
          summary(class: "cursor-pointer font-medium") { "#{row['operation'] == 'retire' ? 'Existing account' : "Record #{row['line']}"}: #{row['operation']} · #{row.dig('after', 'number')} #{row.dig('after', 'name')}" }
          p(class: "mt-2 text-sm text-amber-900") { "Guessed type: #{row['inferred_type']} — check before acceptance." } if row["inferred_type"]
          Array(row["errors"]).each { |error| p(class: "mt-2 text-red-800", role: "alert") { error.to_s } }
          if row["source"]
            dl(class: "mt-3 break-all text-sm") do
              row["source"].each do |field, value|
                dt(class: "mt-2 font-medium") { field }
                dd(class: "whitespace-pre-wrap") { value }
              end
            end
          end
          div(class: "mt-3 grid gap-4 md:grid-cols-2") do
            account("Before", row["before"])
            account("After", row["after"])
          end
        end
      end
    end
    if @token
      form_with(url: tenant_book_chart_import_path(@tid, @bid), method: :patch, data: { turbo: false }) do |f|
        f.hidden_field(:form_token, value: @token)
        f.submit(plan["mode"] == "replace" ? "Accept chart replacement" : "Accept reviewed changes", class: BUTTON)
      end
    else
      p(class: "mt-5 bg-amber-50 p-4") { @data["accepted_command_id"] ? "This review has already been accepted." : "Fix every error and review again before acceptance." }
    end
  end
  def import_mode
    label(for: "import-mode", class: "mt-5 block text-sm font-medium") { "Import mode" }
    select(id: "import-mode", name: "mode", class: FIELD) do
      option(value: "replace", selected: (@data["mode"] || "replace") == "replace") { "Replace chart (default)" }
      option(value: "merge", selected: @data["mode"] == "merge") { "Merge into existing chart" }
    end
    p(class: "mt-2 text-sm text-stone-600") { "Replace uses only the imported rows for the current chart. Matching IDs/numbers retain their identity; omitted accounts move to retired history and release their positions. Merge keeps omitted accounts and checks their positions too. Account numbers remain reserved for their original identities." }
  end
  def create_codes_checkbox
    label(class: "mt-5 flex items-center gap-3 text-sm font-medium") do
      input(type: "checkbox", name: "create_codes", value: "1", checked: @data["create_codes"] == true)
      plain "create type, vat- and category-codes"
    end
    p(class: "mt-2 text-sm text-stone-600") { "Create missing VAT/category codes from unique mapped values, using each code as its name. Existing entries are reused. Account types remain header, calculation or posting." }
  end
  def account(label, data)
    div do
      h3(class: "font-semibold") { label }
      if data
        dl(class: "mt-2 text-sm") do
          %w[kind number name vat_entry_id vat_code category_entry_id category position formula active retired].each do |field|
            dt(class: "mt-2 font-medium") { field }
            dd(class: "whitespace-pre-wrap break-all") { data[field].to_s }
          end
        end
      else
        p { "New account" }
      end
    end
  end
end
