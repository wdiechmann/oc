class Components::JournalVatOperation < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(result:, separator:, fields: {}, url: nil, applied: false)
    @fields, @url, @applied, @options = fields, url, applied, result["vat_options"] || []
    @row, @validation, @separator = result.fetch("row"), result.fetch("validation"), separator
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "VAT operation#{" · ID #{@row['posting_id']}" if @row['posting_id']}" }
    p(class: "mt-3 text-sm text-stone-600") { "The VAT checkbox applies VAT; it never means VAT is included in a result account amount. Debit and credit columns determine posting sides." }
    p(class: "mt-3 font-medium") { "Entered debit amount: #{money(@row['amount_minor'])}" }
    p(class: "mt-2 text-sm") { @row["vat_enabled"] == false ? "VAT is off for this row. Both account amounts stay unchanged." : "VAT is applied from the account’s dated rule. The result account uses a net amount; VAT adjusts the counter-account amount." }
    quotes = Array(@validation["lines"]).filter_map { |line| line["vat"] }
    p(role: "status", class: "mt-3 rounded bg-teal-50 p-3 text-sm") { "VAT selection applied to this row. Save the row or press Enter to record it." } if @applied
    if @url
      form_with(url: @url, method: :post, data: { turbo_stream: true }, class: "mt-4 space-y-3") do |f|
        @fields.except("vat_entry_id", "vat_source_side", "vat_enabled").each do |name, value|
          if value.is_a?(Hash)
            value.each { |key, item| input(type: "hidden", name: "#{name}[#{key}]", value: item) }
          else
            f.hidden_field(name, value: value)
          end
        end
        f.hidden_field(:intent, value: "apply_vat")
        choices = @options.map { |o| [ "#{o['code']} · #{o['name']} · #{Kernel.format('%d.%02d', o['rate_bps'].to_i / 100, o['rate_bps'].to_i % 100)}%", o["vat_entry_id"] ] }
        selected = @row["vat_entry_id"]
        choices << [ "Unavailable VAT selection", selected ] if selected && !choices.any? { |_, id| id == selected }
        div { f.label(:vat_entry_id, "VAT rule for this row"); f.select(:vat_entry_id, choices, { include_blank: "Use the account’s VAT rule", selected: selected }, class: Views::Base::FIELD) }
        source = @row["vat_source_side"] || quotes.first && quotes.first["posting_source_side"] || "debit"
        div { f.label(:vat_source_side, "Account carrying the selected VAT rule"); f.select(:vat_source_side, [ [ "Debit account", "debit" ], [ "Credit account", "credit" ] ], { selected: source }, class: Views::Base::FIELD) }
        div { f.check_box(:vat_enabled, { checked: @row["vat_enabled"] != false, class: "mr-2" }, "true", "false"); f.label(:vat_enabled, "Apply VAT") }
        f.submit("Use on row", class: Views::Base::BUTTON)
        p(class: "text-xs text-stone-500") { "Only this row changes. The posting date selects the dated settings; shared VAT configuration is unchanged." }
      end
    end
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
    p(class: "mt-4 text-sm text-stone-500") { "This previews the current row. Use on row updates the editor; Save or Enter records the row. Non-deductible VAT, if any, follows the configured cost account." }
  end
  def money(value) = JournalMoney.format(value || 0, separator: @separator)
end
