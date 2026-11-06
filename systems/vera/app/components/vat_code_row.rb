class Components::VatCodeRow < Components::Base
  def initialize(data:, entry:, as_of:)
    @data, @entry, @as_of = data, entry, as_of
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    entry = @entry
    rule = @data.fetch("vat_rules").find { |r| r["vat_entry_id"] == entry["id"] && r["active"] && r["valid_from"] <= @as_of.iso8601 && (!r["valid_until"] || r["valid_until"] >= @as_of.iso8601) }
    tr(id: "vat-code-row-#{entry['id']}", class: "border-b last:border-0 hover:bg-teal-50", data: { vat_code_row: entry["id"] }) do
      td(class: "px-4 py-3 font-medium") do
        a(id: "open-vat-code-#{entry['id']}", href: tenant_book_vat_rules_path(@tid, @bid, vat_entry_id: entry["id"], as_of: @as_of.iso8601), data: { turbo_stream: true }, class: "text-teal-900 underline", aria_label: "Open #{entry['code']} · #{entry['name']}") { entry["code"] }
      end
      td(class: "px-4 py-3") { entry["name"] }
      td(class: "px-4 py-3 tabular-nums") { rule ? percentage(rule["rate_bps"]) : "—" }
      td(class: "px-4 py-3 tabular-nums") { rule ? percentage(rule["deductible_bps"]) : "—" }
      td(class: "px-4 py-3") do
        plain(!entry["active"] ? "Inactive" : rule ? "Configured" : "Not configured")
        span(id: "vat-refresh-#{entry['id']}")
      end
    end
  end
  def percentage(bps)
    whole, fraction = bps.to_i.divmod(100)
    "#{whole},#{fraction.to_s.rjust(2, '0')}%"
  end
end
