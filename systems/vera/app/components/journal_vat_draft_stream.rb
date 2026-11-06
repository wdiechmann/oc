class Components::JournalVatDraftStream < Components::Base
  register_element :turbo_stream
  register_element :journal_vat_update
  def initialize(result:, row_id:, separator:)
    @result, @id, @separator = result, row_id, separator
  end
  def view_template
    row = @result.fetch("row")
    quotes = Array(@result.dig("validation", "lines")).filter_map { |l| l["vat"] }
    errors = quotes.any? { |q| q["error"] }
    vat = quotes.sum { |q| q["posting_vat_minor"] || q.dig("amounts", "vat") || 0 }
    hint = quotes.map { |q| q["error"] || "#{q['code']} · VAT #{JournalMoney.format(q['posting_vat_minor'] || q.dig('amounts', 'vat') || 0, separator: @separator)}" }.join(" · ")
    patch = { entry: row["vat_entry_id"], source: row["vat_source_side"], enabled: row["vat_enabled"] != false, credit: row["credit_total_minor"] && JournalMoney.format(row["credit_total_minor"], separator: @separator), vat: errors ? "—" : JournalMoney.format(vat, separator: @separator), hint: hint.presence || "No VAT on this row" }
    turbo_stream(action: "update", target: "vat-operation-row-#{@id}") do
      template { journal_vat_update(hidden: true, data: { row_id: @id, patch: patch.to_json }) }
    end
  end
end
