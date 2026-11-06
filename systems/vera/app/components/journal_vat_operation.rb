class Components::JournalVatOperation < Components::Base
  def initialize(result:, separator:)
    @row, @validation, @separator = result.fetch("row"), result.fetch("validation"), separator
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "VAT operation#{" · ID #{@row['posting_id']}" if @row['posting_id']}" }
    p(class: "mt-3 text-sm text-stone-600") { "The VAT checkbox applies VAT; it never means VAT is included in a result account amount. Debit and credit columns determine posting sides." }
    p(class: "mt-3 font-medium") { "Entered debit amount: #{money(@row['amount_minor'])}" }
    p(class: "mt-2 text-sm") { @row["vat_enabled"] == false ? "VAT is off for this row. Both account amounts stay unchanged." : "VAT is applied from the account’s dated rule. The result account uses a net amount; VAT adjusts the counter-account amount." }
    quotes = Array(@validation["lines"]).filter_map { |line| line["vat"] }
    p(class: "mt-3 text-sm") { "No VAT rule is selected by these accounts." } if quotes.empty? && @row["vat_enabled"] != false
    quotes.each do |quote|
      if quote["error"]
        p(role: "alert", class: "mt-3 text-amber-900") { quote["error"].tr("_", " ") }
      else
        p(class: "mt-3 text-sm") { "#{quote['code']} · #{Kernel.format('%d.%02d', quote['rate_bps'].to_i / 100, quote['rate_bps'].to_i % 100)}% · Net #{money(quote.dig('amounts', 'net'))} · VAT #{money(quote.dig('amounts', 'vat'))}" }
        p(class: "mt-1 text-xs text-stone-500") { "Rule #{quote['rule_id']} · Revision #{quote['rule_version']} · #{quote['date']}" }
      end
    end
    preview = @validation["posting_preview"] || {}
    div(class: "mt-5 overflow-x-auto") do
      table(class: "w-full text-sm") do
        thead { tr { th(class: "p-2 text-left") { "Account" }; th(class: "p-2 text-right") { "Debit" }; th(class: "p-2 text-right") { "Credit" } } }
        tbody do
          Array(preview["rows"]).flat_map { |r| r["legs"] || [] }.each do |leg|
            tr(class: "border-t border-stone-200") do
              td(class: "p-2") { [ leg.dig("account", "number"), leg.dig("account", "name") ].compact.join(" · ") }
              td(class: "p-2 text-right tabular-nums") { money(leg["debit_minor"]) }
              td(class: "p-2 text-right tabular-nums") { money(leg["credit_minor"]) }
            end
          end
        end
      end
    end
    Array(preview["errors"]).each { |error| p(role: "alert", class: "mt-3 text-sm text-amber-900") { error.tr("_", " ") } }
    p(class: "mt-4 text-sm text-stone-500") { "This explains the current row without saving it. Close to change its VAT checkbox or amounts. Non-deductible VAT, if any, follows the configured cost account." }
  end
  def money(value) = JournalMoney.format(value || 0, separator: @separator)
end
