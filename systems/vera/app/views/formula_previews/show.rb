class Views::FormulaPreviews::Show < Views::Base
  ERRORS = { "missing_balance"=>"Enter a test balance for the referenced posting account.", "invalid_reference"=>"A pinned account reference is missing or points to a header.", "formula_cycle"=>"The formula depends on itself through a reference cycle.", "division_by_zero"=>"The formula divides by zero with these test balances.", "invalid_formula"=>"The formula syntax is invalid.", "complexity_limit"=>"The formula exceeds the preview complexity limit.", "amount_out_of_range"=>"The result exceeds the supported amount range." }.freeze
  def initialize(data:, balances: nil, message: nil, **options)
    super(**options)
    @data, @balances, @message = data, balances || data.fetch("balances", {}), message
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @rows = data.fetch("rows")
  end
  def view_template
    div(id: "vera-book-content", class: "min-w-0 break-words") do
      a(href: tenant_book_chart_path(@tid, @bid), class: "text-teal-900 underline") { "← Chart of accounts" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      h1(class: "mt-2 text-3xl font-semibold") { "Formula preview" }
      p(class: "mt-4 text-sm text-stone-600") { "Try the accepted chart formulas with test balances. Enter signed whole minor units (for example, 10000 for 100.00 in a two-decimal currency). Formula constants use the same units. Blank means unknown; enter 0 explicitly for a zero balance. Test balances are not saved." }
      p(class: "mt-3 text-sm text-stone-600") { "References follow saved account identities even after renumbering or reordering. Inactive current accounts remain available and are marked. Arithmetic stays exact through nested formulas; each displayed amount rounds to the nearest minor unit, with ties away from zero." }
      render Components::Toast.new(message: @message, kind: "alert") if @message
      p(class: "mt-4 text-xs text-stone-500") { "Chart revision #{@data.fetch('source_version')} · Test calculation" }
      form_with(url: tenant_book_formula_preview_path(@tid, @bid), method: :post, id: "formula-preview", data: { turbo: false }, class: "mt-6 space-y-4") do |f|
        f.hidden_field(:expected_version, value: @data.fetch("source_version"))
        h2(class: "text-xl font-semibold") { "Posting account test balances" }
        @rows.select { |r| r["kind"] == "posting" }.each do |row|
          div(class: "grid gap-2 rounded-lg border border-stone-200 bg-white p-3 sm:grid-cols-2") do
            label(for: "balance-#{row['id']}", class: "text-sm") { "#{row['number']} · #{row['name']}#{row['active'] ? '' : ' · Inactive'}" }
            input(id: "balance-#{row['id']}", name: "balances[#{row['id']}]", value: @balances[row["id"]], type: "number", step: "1", min: -9_000_000_000_000, max: 9_000_000_000_000, class: FIELD)
          end
        end
        f.submit("Preview formulas", class: BUTTON)
      end
      h2(class: "mt-8 text-xl font-semibold") { "Calculation rows" }
      calculations = @rows.select { |r| r["kind"] == "calculation" }
      p(class: "mt-3 text-sm text-stone-600") { "This chart has no calculation rows." } if calculations.empty?
      calculations.each do |row|
        result = Array(@data["results"]).find { |r| r["account_id"] == row["id"] }
        section(id: "formula-#{row['id']}", class: "mt-4 rounded-xl border border-stone-200 bg-white p-4") do
          h3(class: "font-semibold") { "#{row['name']}#{row['active'] ? '' : ' · Inactive'}" }
          pre(class: "mt-2 whitespace-pre-wrap break-all text-sm") { row["formula"] }
          if result && result["status"] == "ok"
            p(class: "mt-3 text-lg font-semibold text-teal-900") { "Result: #{result['amount_minor']} minor units" }
            p(class: "mt-1 text-xs text-stone-500") { "Exact: #{fraction(result.fetch('exact'))}" }
            details(class: "mt-3", open: true) do
              summary(class: "cursor-pointer text-sm font-medium") { "Referenced accounts" }
              result.fetch("references").each do |ref|
                p(class: "mt-2 text-sm") { "[#{ref['reference']}] → #{account_label(ref)}: #{ref['amount_minor']} minor units (exact #{fraction(ref.fetch('exact'))})" }
              end
            end
            details(class: "mt-3") do
              summary(class: "cursor-pointer text-sm font-medium") { "Underlying posting balances (#{result.fetch('inputs').length})" }
              result.fetch("inputs").each { |r| p(class: "mt-2 text-sm") { "#{account_label(r)}: #{r['balance_minor']} minor units" } }
            end
          elsif result
            related = @rows.find { |r| r["id"] == result["related_account_id"] }
            p(role: "status", class: "mt-3 rounded-lg bg-amber-50 p-3 text-sm") { "#{ERRORS.fetch(result['error'], 'The formula could not be calculated.')}#{related ? " Account: #{account_label(related)}" : ''}" }
          else
            p(class: "mt-3 text-sm text-stone-500") { "Enter test balances and preview to see the result." }
            (row["formula_refs"] || {}).each do |label, id|
              target = @rows.find { |r| r["id"] == id }
              p(class: "mt-2 text-sm") { "[#{label}] → #{target ? account_label(target) : 'Missing account reference'}" }
            end
          end
        end
      end
    end
  end
  def fraction(value) = "#{value.fetch('numerator')}/#{value.fetch('denominator')}"
  def account_label(row) = "#{row['number']} · #{row['name']}#{row['active'] ? '' : ' · Inactive'}"
end
